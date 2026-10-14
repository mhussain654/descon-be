#!/usr/bin/env bash
# Starts a throwaway nginx with deploy/nginx/descon-mps.conf (ports, paths and
# certificate rewritten to a temp directory) in front of a fake Rails upstream
# and a fake SPA build, then asserts the routing the production host depends
# on: API and signed-file paths reach Rails (even when they end in .jpg),
# deep links fall back to index.html, missing assets are 404 (never HTML),
# HTTP never serves the app, and X-Forwarded-For cannot be spoofed.
#
# Needs: nginx, openssl, curl, python3. Runs unprivileged on high ports.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
conf_dir="$here/../nginx"
work="$(mktemp -d)"
http_port=18080
https_port=18443
upstream_port=18300
failures=0

cleanup() {
  [[ -f "$work/nginx.pid" ]] && kill "$(cat "$work/nginx.pid")" 2> /dev/null
  [[ -n "${upstream_pid:-}" ]] && kill "$upstream_pid" 2> /dev/null
  rm -rf "$work"
}
trap cleanup EXIT

command -v nginx > /dev/null || { echo "nginx is required"; exit 2; }

mkdir -p "$work"/{web/assets,acme/.well-known/acme-challenge,tls,snippets,tmp}
echo '<!doctype html><title>SPA</title>' > "$work/web/index.html"
echo 'console.log(1)' > "$work/web/assets/app-abc123.js"
echo 'token-body' > "$work/acme/.well-known/acme-challenge/token"
cp "$conf_dir/descon-security-headers.conf" "$conf_dir/descon-proxy-headers.conf" "$work/snippets/"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=localhost' \
  -keyout "$work/tls/privkey.pem" -out "$work/tls/fullchain.pem" 2> /dev/null

# Fake Rails: echoes the path and the X-Forwarded-For header it received.
cat > "$work/upstream.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def _respond(self):
        length = int(self.headers.get('Content-Length') or 0)
        if length:
            self.rfile.read(length)
        body = f"UPSTREAM {self.path} XFF={self.headers.get('X-Forwarded-For')} PROTO={self.headers.get('X-Forwarded-Proto')}".encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    do_GET = do_POST = _respond
    def log_message(self, *args):
        pass

HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
PY
python3 "$work/upstream.py" "$upstream_port" &
upstream_pid=$!
for _ in $(seq 1 50); do curl -fs "http://127.0.0.1:$upstream_port/ready" > /dev/null 2>&1 && break; sleep 0.1; done

# The production site file with its absolute paths and ports pointed at $work.
sed -e "s#/home/deploy/descon-mps-web/current#$work/web#g" \
    -e "s#/var/www/acme#$work/acme#g" \
    -e "s#/etc/nginx/tls/current#$work/tls#g" \
    -e "s#/etc/nginx/snippets#$work/snippets#g" \
    -e "s#127.0.0.1:3000#127.0.0.1:$upstream_port#g" \
    -e "/\[::\]/d" \
    -e "s#listen 80 default_server#listen $http_port default_server#" \
    -e "s#listen 443 ssl http2 default_server#listen $https_port ssl http2 default_server#" \
    "$conf_dir/descon-mps.conf" > "$work/descon-mps.conf"

cat > "$work/nginx.conf" <<CONF
worker_processes 1;
pid $work/nginx.pid;
error_log $work/error.log;
events { worker_connections 64; }
http {
  # Minimal types: independent of where this nginx build keeps mime.types.
  types { text/html html; text/css css; application/javascript js; image/jpeg jpg jpeg; image/png png; }
  default_type application/octet-stream;
  access_log off;
  client_body_temp_path $work/tmp/body;
  proxy_temp_path $work/tmp/proxy;
  fastcgi_temp_path $work/tmp/fastcgi;
  uwsgi_temp_path $work/tmp/uwsgi;
  scgi_temp_path $work/tmp/scgi;
  include $work/descon-mps.conf;
}
CONF

# -e keeps nginx from trying to open its build-time default error log.
nginx -t -c "$work/nginx.conf" -p "$work" -e "$work/error.log" || { echo "nginx -t failed"; cat "$work/error.log" 2> /dev/null; exit 1; }
nginx -c "$work/nginx.conf" -p "$work" -e "$work/error.log"
for _ in $(seq 1 30); do curl -fsk "https://127.0.0.1:$https_port/" > /dev/null 2>&1 && break; sleep 0.2; done

check() { # description, expected substring, actual
  if [[ "$3" == *"$2"* ]]; then
    echo "  PASS  $1"
  else
    echo "  FAIL  $1 (expected to contain [$2], got [$3])"
    failures=$((failures + 1))
  fi
}
code() { curl -sk -o /dev/null -w '%{http_code}' "$@"; }
body() { curl -sk "$@"; }
headers() { curl -sk -D - -o /dev/null "$@"; }
https="https://127.0.0.1:$https_port"
http="http://127.0.0.1:$http_port"

echo "HTTP (port 80)"
check "ACME challenge is served" "token-body" "$(body "$http/.well-known/acme-challenge/token")"
check "everything else redirects to HTTPS" "301" "$(code "$http/api/v1/auth/login")"
# $host carries no port, so the test's non-standard port is dropped -- as it is
# on the real host, where the HTTPS port is the default 443.
check "the redirect keeps the path" "https://127.0.0.1/admin" "$(headers "$http/admin" | grep -i '^location:')"

echo "Admin SPA"
check "/ serves the shell" "<title>SPA</title>" "$(body "$https/")"
check "the shell is never cached" "no-store" "$(headers "$https/" | grep -i '^cache-control:')"
check "security headers are present" "nosniff" "$(headers "$https/" | grep -i '^x-content-type-options:')"
check "a deep link falls back to the shell" "<title>SPA</title>" "$(body "$https/admin/candidates/123")"
check "a fingerprinted asset is cached for a year" "immutable" "$(headers "$https/assets/app-abc123.js" | grep -i '^cache-control:')"
check "a missing asset is 404, never the shell" "404" "$(code "$https/assets/missing.js")"
check "a missing file with an extension is 404" "404" "$(code "$https/nope.png")"

echo "Rails API"
check "/api/v1 reaches Rails" "UPSTREAM /api/v1/health/ready" "$(body "$https/api/v1/health/ready")"
check "a signed file URL ending in .jpg reaches Rails" "UPSTREAM /rails/active_storage/blobs/proxy/abc/photo.jpg" \
  "$(body "$https/rails/active_storage/blobs/proxy/abc/photo.jpg")"
check "X-Forwarded-Proto is https" "PROTO=https" "$(body "$https/api/v1/x")"
check "a client-supplied X-Forwarded-For is overwritten" "XFF=127.0.0.1" \
  "$(body -H 'X-Forwarded-For: 6.6.6.6' "$https/api/v1/x")"
head -c 9437184 /dev/zero > "$work/big.bin"
check "an oversized body is rejected" "413" "$(code -X POST --data-binary "@$work/big.bin" "$https/api/v1/x" --max-time 10)"

echo "Paths that must not fall through to the shell"
check "/api/other is 404" "404" "$(code "$https/api/other")"
check "/rails/other is 404" "404" "$(code "$https/rails/other")"
check "/api-docs is 404" "404" "$(code "$https/api-docs/index.html")"
check "/openapi is 404" "404" "$(code "$https/openapi/openapi.yaml")"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "nginx routing: all checks passed."
else
  echo "nginx routing: $failures check(s) FAILED. nginx error log:"
  tail -20 "$work/error.log" 2> /dev/null
  exit 1
fi
