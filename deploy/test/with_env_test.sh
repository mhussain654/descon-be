#!/usr/bin/env bash
# Behavioral test for deploy/bin/with-env (run locally and in CI).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
wrapper="$here/../bin/with-env"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

check() { # description, expected, actual
  if [[ "$2" == "$3" ]]; then
    echo "  PASS  $1"
  else
    echo "  FAIL  $1 (expected [$2], got [$3])"
    failures=$((failures + 1))
  fi
}

cat > "$work/env" <<'ENVFILE'
# a comment

PLAIN=hello
WITH_DOLLAR=pa$$w0rd$HOME
WITH_BACKTICK=a`id`b
WITH_SUBSHELL=$(touch INJECTED)
WITH_SPACES=two words here
WITH_EQUALS=a=b=c
ALREADY_SET=from-file
not a valid line
9STARTS_WITH_DIGIT=ignored
ENVFILE

run() { DESCON_ENV_FILE="$work/env" "$wrapper" "$@"; }
cd "$work" || exit 1

check "a plain value is exported" "hello" "$(run printenv PLAIN)"
# The single-quoted expectations below are literal on purpose: they are the
# bytes that must come back unexpanded.
# shellcheck disable=SC2016
check "dollar signs are taken literally" 'pa$$w0rd$HOME' "$(run printenv WITH_DOLLAR)"
# shellcheck disable=SC2016
check "backticks are taken literally" 'a`id`b' "$(run printenv WITH_BACKTICK)"
# shellcheck disable=SC2016
check "command substitution is never executed" '$(touch INJECTED)' "$(run printenv WITH_SUBSHELL)"
check "no file was created by injection" "no" "$([[ -e INJECTED ]] && echo yes || echo no)"
check "spaces and = survive" "two words here|a=b=c" "$(run printenv WITH_SPACES)|$(run printenv WITH_EQUALS)"
check "a malformed or digit-led key is ignored" "" "$(run printenv 9STARTS_WITH_DIGIT 2>/dev/null)"
check "a variable already set in the environment wins" "from-caller" \
  "$(ALREADY_SET=from-caller run printenv ALREADY_SET)"
check "the wrapped command's exit status is preserved" "7" "$(run bash -c 'exit 7'; echo $?)"

DESCON_ENV_FILE="$work/missing" "$wrapper" true 2> /dev/null
check "a missing environment file is a hard error (78)" "78" "$?"

printf 'PLAIN=overridden\nONLY_IN_OVERRIDE=yes\n' > "$work/override"
check "an override file wins over the main file" "overridden" \
  "$(DESCON_ENV_OVERRIDE_FILE="$work/override" run printenv PLAIN)"
check "an override file can add variables" "yes" \
  "$(DESCON_ENV_OVERRIDE_FILE="$work/override" run printenv ONLY_IN_OVERRIDE)"
check "the main file is still loaded alongside an override" 'a=b=c' \
  "$(DESCON_ENV_OVERRIDE_FILE="$work/override" run printenv WITH_EQUALS)"
DESCON_ENV_OVERRIDE_FILE="$work/no-such-override" run true 2> /dev/null
check "an unreadable override file is a hard error (78)" "78" "$?"

echo
if [[ "$failures" -eq 0 ]]; then echo "with-env: all checks passed."; else echo "with-env: $failures check(s) FAILED."; exit 1; fi
