# AWS EC2 deployment runbook (backend)

> **Domain transition (October 2026).** The public origin is now
> `https://descon-mps.com` (web at `/`, Rails at `/api/v1/`). Section 3.6
> records the original IP certificate setup. After these PRs merge, confirm
> the domain A record points to `52.221.51.231`, then on the instance issue
> `sudo /snap/bin/certbot certonly --webroot --webroot-path /var/www/acme -d descon-mps.com --deploy-hook "systemctl reload nginx"`. Point
> `/etc/nginx/tls/current` at `/etc/letsencrypt/live/descon-mps.com`, run
> `sudo nginx -t && sudo systemctl reload nginx`, and test
> `curl -fsSI https://descon-mps.com/` and `sudo /snap/bin/certbot renew --dry-run`.
> Update `/home/deploy/descon-mps-api/shared/.env` with the three public URLs
> in `deploy/shared.env.example` and restart Rails. Set the frontend GitHub
> `PUBLIC_ORIGIN` variable to `https://descon-mps.com` and rebuild/redeploy it.
> The template and merged code do not change server secrets or existing builds.
> Keep SSH/Capistrano on the Elastic IP. Register the new KuickPay return URL
> before enabling payments.

> **Preview shares the live test host.** Both GitHub environments deploy the Rails API
> to `/home/deploy/descon-mps-api/current` on the same EC2 instance and use
> the same RDS databases and S3 bucket. A branch or PR preview replaces the
> currently served API and may migrate shared databases. Deploying `main`
> later replaces its code, but rollback cannot undo migrations. Use a
> separate host and data stores before treating preview as isolated staging.

First production-shaped deployment of the Rails API to one Ubuntu 24.04 EC2
instance in `ap-southeast-1`, with Nginx as the only public entry point, a
private RDS PostgreSQL database and a private S3 bucket. The admin web app is
deployed by the `descon-fe` repository onto the same instance and shares the
host-wide deploy lock described below.

> **Status.** This is a *test-environment* deployment. It is not production
> ready: malware scanning deliberately off (see §5), no email (SES deferred), the mock SMS
> provider unless send.pk credentials are added, KuickPay disabled, and a
> short-lived IP-address certificate. See [What is and is not verified](#what-is-and-is-not-verified).

## 1. Topology

```
Internet ──443──► Nginx (only public listener; 80 serves just the ACME challenge + redirect)
                    ├─ /api/v1/…                 → Puma   127.0.0.1:3000   (Rails API + Solid Queue)
                    ├─ /rails/active_storage/…   → Puma   (signed, short-lived file URLs)
                    └─ everything else           → /home/deploy/descon-mps-web/current  (static admin SPA)

Puma ──TLS (verify-full)──► RDS PostgreSQL 17  (4 databases: primary, cache, queue, cable)
Puma ──instance role──────► S3 bucket (private, SSE-S3)
```

Ports 3000 and 4000 are not public: the EC2 security group allows only 80/443
(and SSH from the administrator's IP), and Puma binds `127.0.0.1` only. There
is no Node/Hono process: the admin web app is built as a static SPA.

One origin serves both the web app and the API, so there are no cross-origin
requests and CORS is only a safeguard. A domain can be added later without
restructuring (see [Adding a domain](#10-adding-a-domain-later)).

## 2. Findings: where the handoff and the code differ

Verified by reading and running the code. Each one is handled in this change
or listed under [Open decisions](#12-open-decisions).

| # | Handoff / expectation | What the code actually does | Handled by |
|---|---|---|---|
| 1 | Puma listens on `127.0.0.1:3000` | `config/puma.rb` binds `0.0.0.0` (`port ENV['PORT']`) | systemd unit passes `-b tcp://127.0.0.1:3000`, which replaces the `port` line (verified) |
| 2 | Solid Queue in Puma saves memory | The plugin's default `fork` mode starts a supervisor **plus** worker, dispatcher and scheduler processes: 5 processes instead of 1 (measured, §7) | New `SOLID_QUEUE_MODE=async` switch in `config/puma.rb` |
| 3 | `SOLID_QUEUE_IN_PUMA` toggles the plugin | Any non-nil string enabled it, including `SOLID_QUEUE_IN_PUMA=` and `=false` | `config/puma.rb` now treats empty, `0`, `false`, `no`, `off` as disabled |
| 4 | Backup job covers "all required databases" | `Backups::CreateDatabaseBackupJob` dumps the **primary** database only. Cache/queue/cable hold regenerable or in-flight state and are intentionally not dumped | Documented (§6) |
| 5 | Backup retention | There is none: each night's archive stays in S3 forever, and S3 keys are random with no prefix, so a lifecycle rule cannot target them | Documented; needs a product decision (§12) |
| 6 | Restore procedure | `backups:restore` refuses to run inside a production process; there is no in-app restore for production | Manual procedure (§6) |
| 7 | "Verified RDS TLS" | `database.yml` has no `sslmode`; libpq reads `PGSSLMODE`/`PGSSLROOTCERT` for both the app and `pg_dump` | `deployment:preflight` fails on remote DB without verified TLS in production |
| 8 | Credentials | `sendpk.production.api_key` and `kuickpay.production.secured_key` come from **encrypted credentials** (`RAILS_MASTER_KEY`), not env; `CORS_ALLOWED_ORIGINS` and the three Active Record encryption keys have no production default and stop boot if missing | `shared.env.example`, preflight credential check |
| 9 | Routing: `/` → web, `/api/v1/` → Rails | Document and photo URLs are **path-only** `/rails/active_storage/blobs/proxy/…`, resolved against the same origin. They must reach Rails too, and they end in `.jpg`/`.pdf`, so Nginx's static-file rules would swallow them without `^~` | `deploy/nginx/descon-mps.conf` + routing test |
| 10 | README: `SMS_PROVIDER` — `test` is the only implementation | A real `sendpk` provider exists (`app/services/sms/providers/sendpk_provider.rb`) | README corrected |
| 11 | `APP_ENV=staging` is "the test switch" | It only affects the malware scanner guard (grep: no other use) | Documented (§5) |
| 12 | Ubuntu packages | apt's Certbot is too old for IP-address certificates (needs ≥ 5.4); Ubuntu 24.04's nginx 1.24 has no `http2 on;` directive; PostgreSQL client 16 cannot dump a 17 server | §3, config uses `listen … http2` |
| 13 | Docker entrypoint runs `db:prepare` | Not used here (no Docker); migrations are run explicitly by the deploy | Capistrano `deploy:db_prepare` |
| 14 | Staff invitation email builds a link | The email carries only a token (no URL), and SES is deferred, so invitations are not deliverable yet; `action_mailer.default_url_options` is `example.com` and unused today | §9 |
| 15 | — | Booting in production logs a harmless `image_processing` gem warning (variant processor); no code path used here needs variants | Ignore |

## 3. One-time administrator tasks

Already done (per the infrastructure handoff, **not** re-verified from this
repository): AWS account/region, EC2 instance + Elastic IP, security group,
`deploy` user, rbenv Ruby 3.4.7, nvm Node, Nginx installed, RDS and its four
databases, S3 bucket + instance role policy, GitHub deploy keys.

Everything below is still to do. Commands are run on the instance as a user
with sudo (`ubuntu`) unless noted. Never paste secrets into a ticket or chat.

### 3.1 Packages

```bash
sudo apt-get update
# Build dependencies for the gems with native extensions (pg, bootsnap, …)
sudo apt-get install -y build-essential libpq-dev libyaml-dev libffi-dev zlib1g-dev git curl
# PostgreSQL 17 client tools from the PostgreSQL project's apt repository
sudo apt-get install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt-get install -y postgresql-client-17
/usr/lib/postgresql/17/bin/pg_dump --version      # expect: pg_dump (PostgreSQL) 17.x
```

The unit file and Capistrano put `/usr/lib/postgresql/17/bin` first on `PATH`,
so the nightly backup job's bare `pg_dump` resolves to version 17.

Bundler 4 (the lockfile's `BUNDLED WITH`) for the deploy user:

```bash
sudo -iu deploy bash -c 'export RBENV_ROOT=$HOME/.rbenv PATH=$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH; gem install bundler -v 4.0.0 --no-document'
```

### 3.2 RDS certificate bundle (verified TLS)

```bash
sudo install -d -m 0755 /etc/ssl/rds
sudo curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /etc/ssl/rds/global-bundle.pem
```

Prove verification works with a real login (prompts for the password; nothing
goes on the command line):

```bash
psql "host=descon-mps-db.czkga408o68a.ap-southeast-1.rds.amazonaws.com port=5432 dbname=descon_mps_production user=<role> sslmode=verify-full sslrootcert=/etc/ssl/rds/global-bundle.pem" -c 'select version()'
```

### 3.3 Protected environment file

```bash
sudo -iu deploy bash -c 'install -d -m 0755 /home/deploy/descon-mps-api/shared && install -d -m 0755 /home/deploy/descon-mps-api/shared/bin'
# copy deploy/shared.env.example to /home/deploy/descon-mps-api/shared/.env, fill it in, then:
sudo chown deploy:deploy /home/deploy/descon-mps-api/shared/.env
sudo chmod 0600 /home/deploy/descon-mps-api/shared/.env
```

Generate the secrets on the instance (they never need to exist anywhere else):

```bash
openssl rand -hex 64      # JWT_SECRET
openssl rand -hex 64      # INVITATION_TOKEN_SECRET
```

`bin/rails db:encryption:init` (run from any checkout, e.g. a laptop) prints
the three Active Record encryption values. **Store a separate offline copy**:
losing them makes every encrypted CNIC/passport column unreadable.

`RAILS_MASTER_KEY` is the content of `config/master.key`. Before first boot
confirm the encrypted credentials contain the **production** keys that will be
needed (`bin/rails credentials:edit`): `sendpk: { production: { api_key } }`
only if `SMS_PROVIDER=sendpk`, and `kuickpay: { production: { secured_key } }`
only if `KUICKPAY_ENABLED=true`. `deployment:preflight` reports which are
present (as booleans, never values).

### 3.3.1 Database roles (recommended, optional)

Today the application uses the RDS master login. A restricted runtime role is
feasible because the app only needs DML at run time; schema changes happen only
in `db:prepare` at deploy time:

* `descon_owner` — owns the schema, used **only** by the migration step.
* `descon_app` — `SELECT/INSERT/UPDATE/DELETE` on tables and `USAGE, SELECT` on
  sequences (this is also all `pg_dump` needs), used by Puma and Solid Queue.

Run once per database (all four) as the master user, via `psql` so passwords
are typed at the `\password` prompt and never appear in history or argv:

```sql
CREATE ROLE descon_owner LOGIN;  \password descon_owner
CREATE ROLE descon_app   LOGIN;  \password descon_app
-- repeat for descon_mps_production, _cache, _queue, _cable:
ALTER DATABASE descon_mps_production OWNER TO descon_owner;
\c descon_mps_production
ALTER SCHEMA public OWNER TO descon_owner;
ALTER DEFAULT PRIVILEGES FOR ROLE descon_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO descon_app;
ALTER DEFAULT PRIVILEGES FOR ROLE descon_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO descon_app;
```

Then put `descon_app`'s credentials in `shared/.env` and the owner's
`DB_USERNAME`/`DB_PASSWORD` only in `shared/.env.migrate` (0600, deploy). When
that file exists, `deploy:db_prepare` loads it through
`DESCON_ENV_OVERRIDE_FILE`, so the owner password is used for that one command
and is never in git, logs or a command line. Tables created *before* the
default privileges must be granted once with `GRANT … ON ALL TABLES IN SCHEMA
public TO descon_app` (and `… SEQUENCES`). **Not rehearsed against RDS** — try
it on the empty test database first.

### 3.4 systemd and sudoers

```bash
sudo install -m 0644 deploy/systemd/descon-mps-api.service /etc/systemd/system/descon-mps-api.service
sudo install -m 0440 deploy/sudoers/descon-mps-deploy /etc/sudoers.d/descon-mps-deploy
sudo visudo -cf /etc/sudoers.d/descon-mps-deploy        # must print: parsed OK
sudo systemctl daemon-reload
sudo systemctl enable descon-mps-api.service            # do not start it yet: no release exists
sudo usermod -aG systemd-journal deploy                 # read-only log access, no sudo
```

The sudoers file grants exactly
`sudo -n /usr/bin/systemctl restart descon-mps-api.service` and nothing else.

### 3.5 Deploy user: GitHub host key and Capistrano

```bash
sudo -iu deploy git ls-remote git@github-mps-backend:mhussain654/descon-be.git HEAD
```

This must succeed without a prompt. Capistrano's git wrapper uses
`StrictHostKeyChecking=yes`, so GitHub's key must already be in
`~deploy/.ssh/known_hosts`. Verify it against GitHub's published fingerprints
before trusting it.

On the administrator's machine, add the instance's host key (compare the
fingerprint with the EC2 console / `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`
on the instance):

```bash
ssh-keyscan -t ed25519 52.221.51.231 >> ~/.ssh/known_hosts
```

### 3.6 Nginx and TLS for the Elastic IP

1. Install the bootstrap (HTTP-only) site and the snippets:

   ```bash
   sudo install -d /var/www/acme /etc/nginx/snippets
   sudo install -m 0644 deploy/nginx/descon-security-headers.conf deploy/nginx/descon-proxy-headers.conf /etc/nginx/snippets/
   sudo install -m 0644 deploy/nginx/descon-mps-bootstrap.conf /etc/nginx/sites-available/descon-mps
   sudo ln -sf /etc/nginx/sites-available/descon-mps /etc/nginx/sites-enabled/descon-mps
   sudo rm -f /etc/nginx/sites-enabled/default
   sudo nginx -t && sudo systemctl reload nginx
   ```

2. Install a Certbot that supports IP addresses. **apt's Certbot is too old**
   (IP certificates need Certbot ≥ 5.3, and ≥ 5.4 for `--webroot`):

   ```bash
   sudo snap install --classic certbot
   certbot --version      # must be 5.4 or newer; if not, stop here
   ```

3. Issue against the staging CA first (not browser-trusted), then for real. Let's
   Encrypt IP certificates are only available through the `shortlived` profile
   (about 6 days) and HTTP-01:

   ```bash
   sudo certbot certonly --staging --preferred-profile shortlived \
     --webroot --webroot-path /var/www/acme --ip-address 52.221.51.231
   sudo certbot certonly --preferred-profile shortlived --force-renewal \
     --webroot --webroot-path /var/www/acme --ip-address 52.221.51.231 \
     --deploy-hook 'systemctl reload nginx'
   ```

4. Point Nginx at the certificate through one symlink (the only thing a domain
   change touches) and install the real site:

   ```bash
   sudo install -d /etc/nginx/tls
   sudo ln -sfn /etc/letsencrypt/live/52.221.51.231 /etc/nginx/tls/current
   sudo install -m 0644 deploy/nginx/descon-mps.conf /etc/nginx/sites-available/descon-mps
   sudo nginx -t && sudo systemctl reload nginx
   ```

5. **Prove unattended renewal before claiming HTTPS is ready** — a 6-day
   certificate that silently stops renewing takes the site down within a week:

   ```bash
   sudo certbot renew --dry-run
   systemctl list-timers | grep -i certbot            # renewal timer present and scheduled
   sudo openssl x509 -in /etc/nginx/tls/current/fullchain.pem -noout -enddate
   ```

   Re-check `-enddate` a few days later; it must have moved forward on its own.
   Certbot's installer plugins do not support IP certificates yet, so the
   deploy hook and the manual Nginx paths above are required.

**Until step 5 passes, treat HTTPS as unproven.** Do not enter real candidate
logins or upload real documents over plain HTTP (port 80 serves nothing but
the challenge and a redirect).

### 3.7 SSM and CD prerequisites (only for continuous delivery, §11)

Attach `AmazonSSMManagedInstanceCore` to the instance role
(`descon-mps-app-role`) and confirm the instance is "Online" in Systems
Manager → Fleet Manager.

## 4. First deployment and day-to-day deploys

From a checkout of this repository on an administrator machine whose IP is
allowed by the SSH security group:

```bash
bundle install                                   # includes the :deploy group
bundle exec cap production deploy:check
bundle exec cap production deploy                # branch main
```

`BRANCH=<name>` deploys another branch; `REVISION=<40-char sha>` deploys an
exact commit (this is what CD uses).

What a deploy does, in order (`config/deploy.rb`):

1. Takes the host-wide lock (`/home/deploy/.deploy-locks/descon-mps.lock`).
   A second deploy — backend **or** frontend — fails fast naming the holder.
2. Uploads `shared/bin/with-env`, clones/updates the repository mirror with
   strict host-key checking, creates `releases/<timestamp>`, links shared dirs.
3. `bundle install` into `shared/bundle` (without development, test, deploy).
4. `rake deployment:preflight` (new release, loaded environment): all four
   databases reachable, remote TLS verified, `pg_dump` ≥ server, S3 reachable,
   needed credentials present, scanner mode reported. **A failure stops the
   deploy before anything is migrated or switched.**
5. `rake db:prepare` with `DB_STATEMENT_TIMEOUT_MS=0`: creates/migrates all four
   databases. On a database that was empty it also loads the schema and runs
   the idempotent seeds **once** (roles, permissions, workflow stages, the six
   stage call scripts). Nothing is demo data (`SEED_DEMO_DATA` is dev-only).
6. Switches `current`, restarts `descon-mps-api.service`, then polls
   `/api/v1/health/ready` on loopback (30 × 2 s).
7. If the new release is not healthy, `current` is re-pointed at the release
   that was serving **before** this deploy, the service is restarted, health is
   re-checked, and the failed release directory is deleted. The deploy exits
   non-zero and says whether the restored release is healthy.

Migrations are applied *before* the switch, so every migration must be
backward compatible with the release that is still running (add before use,
remove in a later deploy — see AGENTS.md). A rollback restores code, never
data: it does not undo migrations.

First-ever deploy only, after it succeeds:

```bash
sudo systemctl status descon-mps-api.service     # enabled earlier; the deploy restarted it
bundle exec cap production deploy:queue_status   # worker + dispatcher alive
```

### First staff administrator

Seeds do not create a user, and invitations need an existing administrator
plus email (deferred). Create the first one directly (the password is read
from the process environment of one shell, never from argv or history):

```bash
sudo -iu deploy
cd /home/deploy/descon-mps-api/current
read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
/home/deploy/descon-mps-api/shared/bin/with-env env RAILS_ENV=production \
  RBENV_ROOT=$HOME/.rbenv RBENV_VERSION=3.4.7 PATH=$HOME/.rbenv/bin:$PATH \
  rbenv exec bundle exec rails runner \
  "User.create!(email: 'admin@your-domain', password: ENV.fetch('ADMIN_PASSWORD'), role: 'admin', active: true)"
unset ADMIN_PASSWORD
```

The `User` model validates the email, a Devise password and
the role (`admin hr mps finance management`); `staff_state` defaults to
`active`. Change the password after the first sign-in.

### Rollback

```bash
bundle exec cap production deploy:rollback       # previous release, restarted and health-checked
```

### Logs and health

```bash
sudo journalctl -u descon-mps-api.service -f     # as deploy, after the systemd-journal group
curl -fsS http://127.0.0.1:3000/api/v1/health/ready      # on the instance
curl -fsS https://52.221.51.231/api/v1/health/ready      # through Nginx/TLS, from anywhere
bundle exec cap production deploy:storage_round_trip     # S3 upload/read/sign/refuse-unsigned/delete
```

## 5. Malware scanning

### Production decision: scanning is deliberately off

**Decision (2026-10-17).** Production runs **without malware scanning**. The
client has not asked for it, and a scanner costs RAM (ClamAV needs about
1-1.5 GB) or a second server. It will be added when the client requests it.

```
APP_ENV=production
DOCUMENT_MALWARE_SCANNER=none
```

* `none` is an explicit opt-out and is never the default. With the variable
  **unset**, every document upload is still refused (`503
  malware_scan_unavailable`).
* Every file is accepted unscanned. What still applies: allowed file types and
  size limits, private S3 storage, time-limited signed URLs, and the staff
  permission checks.
* The application warns at boot, on each upload and in `deployment:preflight`
  (`[WARN] malware scanner: scanning DISABLED ...`). The warning does not stop
  a deploy.
* **Accepted risk:** an infected file uploaded by a candidate would be opened
  by HR staff on their own computers. Nothing in the database marks a file as
  scanned or unscanned.
* **To turn scanning on later:** add a provider (for example ClamAV on a
  separate small server, or GuardDuty Malware Protection for S3), register it in
  `MalwareScanning::Configuration::PROVIDERS`, set `DOCUMENT_MALWARE_SCANNER` to
  its code, and run the acceptance test at the end of this section.

### Test environment (the mock scanner)

**Current state of the code.** `MalwareScanning::Configuration` accepts only
the `mock` provider, and only when `APP_ENV` is `development`, `test` or
`staging`. The mock flags a file containing the EICAR test signature and
passes **every other file**. A live deployment (`APP_ENV=production`, unset
with `RAILS_ENV=production`, or any unrecognised value) refuses to boot with
`mock` and, with no scanner, refuses every upload (`503 malware_scan_unavailable`).

**Smallest explicit opt-in for this test host** — no code change is needed
and none is made, because the guard already does what is asked:

```
APP_ENV=staging
DOCUMENT_MALWARE_SCANNER=mock
```

Both lines are required and both are explicit; forgetting `APP_ENV` fails
closed. `APP_ENV=staging` changes nothing else in the application (verified by
search).

**Which uploads are allowed.** Candidate document and bank-proof uploads are
accepted after the EICAR check only. They are *not* scanned for malware.
There is no per-document "scanned" state in the schema, so nothing in the
database, API or UI marks a file as safe — and nothing marks it as unscanned.

**What operators and staff see.** Operators: a `WARN` at boot and on each
provider resolution, and `deployment:preflight` reports `[WARN] malware
scanner: MOCK …` on every deploy. Staff and candidates see nothing different.
**Therefore real candidate documents must not be uploaded to this host**; use
synthetic files only. Do not turn this host into a place where staff review
real documents until a scanner is integrated.

**Disabling the temporary mode.** Remove `DOCUMENT_MALWARE_SCANNER` from
`shared/.env` (uploads are then refused, fail closed), or set
`APP_ENV=production` (the application refuses to boot while `mock` remains).

**Decision this needs, not made here.** Showing staff that a document was
not scanned requires a stored per-document scan outcome (scanner, time,
result) and UI — a schema and product change. It is deliberately not added
silently.

**Acceptance test for enabling a real scanner** (on the staging copy first):

1. Add the provider adapter (`infected?(io:, filename:)`) to
   `MalwareScanning::Configuration::PROVIDERS`, and set
   `DOCUMENT_MALWARE_SCANNER=<code>`, `APP_ENV=production`.
2. App boots; `deployment:preflight` shows `[PASS] malware scanner: provider <code>`.
3. Uploading the EICAR test file returns `malware_detected` and stores nothing.
4. Uploading a clean PDF is accepted and retrievable.
5. With the scanner unreachable, uploads return `503 malware_scan_unavailable`
   (fail closed) and nothing is stored.
6. Setting `DOCUMENT_MALWARE_SCANNER=mock` with `APP_ENV=production` stops boot.

## 5a. Automatic voice calls (RoboCall)

Calls are placed by **RoboCall.pk**, which plays a fixed pre-recorded voice. The
app sends only a `voice_id` and the candidate's number; there are no variables
and no live conversation.

* **Credentials.** `robocall.production.api_key` in the encrypted credentials
  (`bin/rails credentials:edit`). `deployment:preflight` fails if the key is
  missing while `AI_VOICE_OUTBOUND_ENABLED=true`.
* **Environment.** `AI_VOICE_PROVIDER=robocall` (the default) and
  `AI_VOICE_OUTBOUND_ENABLED=true` to start. Switching the flag off stops every
  new call at once (kill switch). Calling hours, the daily cap and the cooldown
  are edited in the admin app (AI call settings).
* **What triggers a call.** A candidate entering a workflow stage whose row
  (admin app, **Automatic calls**) is active and has a voice ID. At most one
  call per candidate per stage; a stage with no voice places no call.
* **Results.** RoboCall has no webhook, so `AiCalls::PollRobocallCallsJob`
  (every minute) reads each open call's status. Status 2 answered, 3
  congestion, 4 busy, 5 no answer, 6 hangup. A key press of 3 is recorded as
  "callback required". RoboCall retries unanswered calls on its own (Call
  Settings panel: retry delay and count; we use a 5-10 minute delay), so a
  not-answered status only counts as final after
  `ROBOCALL_RETRY_WINDOW_MINUTES` (default 30; set it to retry delay x
  retries plus a few minutes). A call with no final result 15 minutes after
  that window goes to manual review.
* **Check before going live** (read-only except `call`):

  ```
  bin/rails ai_calls:robocall:check                       # key valid + balance
  bin/rails "ai_calls:robocall:call[VOICE_ID,923001234567]"   # ONE real, charged call
  bin/rails "ai_calls:robocall:status[CALL_ID]"           # status code + key press
  ```
* **What is sent.** Only the destination number and the `voice_id` (GET
  `https://portal.robocall.pk/api/calls`, the URL shown in the RoboCall portal;
  `ROBOCALL_BASE_URL` overrides it). RoboCall's portal documentation marks
  `amount`, `key1`, `key2`, `text1` and `text2` as required while its public
  page lists them as optional. We send none of them, by decision (the voices
  are fixed recordings). If RoboCall answers a call with a bad-request error,
  `ai_calls:robocall:call` shows it on the first test and these fields would
  need adding in `AiCalls::Providers::RobocallAdapter#initiate_call`.
* **Call id.** The portal's sample response shows `order_id` where the written
  docs say `call_id`; the adapter accepts either. If RoboCall accepts a call
  but returns neither, the call is kept and sent to manual review (never rolled
  back, which would call the candidate twice).
* **Bulk.** RoboCall also has `/api/mutliple_calls` (their spelling;
  comma-separated numbers in `caller_id`), but its response for several numbers
  is not documented. `bin/rails "ai_calls:robocall:multiple[VOICE_ID,923001234567 923007654321]"`
  places REAL calls to those numbers and prints the raw response, to see
  whether it returns one id per number before anything depends on it.
* **Calling one candidate** (admin app: candidate page > **AI calls** tab, needs
  `trigger_ai_calls`). The dropdown lists only the **active** call types (the same
  library as Bulk calls). The same call type can be placed to the same candidate
  again after the cooldown (default 15 minutes; AI call settings or
  `AI_VOICE_OUTBOUND_TRIGGER_COOLDOWN_MINUTES`); a different call type can be placed
  at once. The tab's history lists every call the candidate had: manual, automatic
  (stage) and bulk, with the call type name and the result.
* **Bulk calls** (admin app: *Bulk calls*, `/admin/bulk-calls`). An admin picks one
  workflow stage and one **call type** (a named RoboCall voice, kept in
  `robocall_voices`; adding or editing one needs `manage_ai_call_scripts`), sees
  who at that stage is still to be called, and starts a batch for the next few.
  Using the page and starting a batch need `trigger_ai_calls`.
  * **Where the voices live.** Call types are database rows, not code. The first
    approved ones (536 medical date and center added, 537 medical report received,
    538 upload documents) are installed by a migration from the single list in
    `AiCalls::InstallStarterRobocallVoicesService`, and each is also set as the
    voice of its stage (`medical_appointment`, `medical_fit`,
    `documents_pending`) with the stage left **off**. **To add the next voice:**
    *Bulk calls* > *Call types* > *Add call type* (name, Urdu name, RoboCall voice
    ID); to have it called automatically, open *Automatic calls*, put the same
    voice ID on the stage and switch the stage on. No deploy needed.
  * **One batch, at most `ROBOCALL_BULK_BATCH_LIMIT` candidates** (default 200),
    enforced by the backend as well as the page. Start it again for the rest:
    anyone already called with that voice, or still queued in a batch, is
    skipped, so each run takes the next group.
  * **"Already called"** means a call with that voice exists for the candidate's
    current assignment (from a bulk batch or an automatic stage call), or one is
    still queued. Candidates who were skipped (moved stage, inactive, outside
    hours, daily limit) or failed (RoboCall could not take it) are picked up again
    by a later batch.
  * **Sending.** Starting a batch only records it (`bulk_call_batches`, one
    `bulk_call_batch_items` row per candidate) and queues one job each, spaced
    `ROBOCALL_BULK_CALL_SPACING_SECONDS` apart (default 2), because RoboCall
    documents no rate limit. Each call goes through the same safety controls as
    any outbound call.
  * **Refused up front, nothing queued:** outbound calling off, outside the
    calling hours, a limit above the ceiling, a switched-off call type, nobody
    left to call, or a batch larger than what remains of today's daily call limit
    (the default is 1000 a day, so several batches of up to 200 fit in a day; change it in AI call settings).
  * **A batch counts as one admin action**, so the per-admin hourly limit does
    not apply to its calls, and the per-reason cooldown is replaced by the
    per-voice "already called" rule.
  * **Results** (`/admin/bulk-calls/<id>`) show each candidate's result and call
    outcome and refresh while calls are waiting. RoboCall's own retries and the
    retry window above apply to every call in a batch.
* **The api key travels in the query string** (RoboCall's design). The adapter
  never logs a URL and raises only fixed messages; keep it that way, and do not
  enable HTTP request logging for this host.
* The ElevenLabs provider is still in the code and is selected with
  `AI_VOICE_PROVIDER=elevenlabs`; it is not used.

## 6. Backups: what exists and how to restore

`Backups::CreateDatabaseBackupJob` runs from `config/recurring.yml` at
**00:00 UTC (05:00 Pakistan time)** every day:

* `pg_dump --format=plain --clean --if-exists --no-owner --no-privileges` of
  the **primary** database only, gzipped, attached privately through Active
  Storage to the S3 bucket, with a SHA-256 checksum recorded in
  `system_database_backups`. Administrators can list and download them
  (`/api/v1/admin/system_database_backups`).
* It shells out to `pg_dump` on `PATH` and passes the password via
  `PGPASSWORD`. TLS settings come from `PGSSLMODE`/`PGSSLROOTCERT`.
* A failed night leaves a `failed` row (visible to admins) and is retried the
  next night; only the upload step retries automatically.
* **No retention.** Old archives are never deleted (see §12).
* The cache, queue and cable databases are not dumped (cache is regenerable,
  queue/cable hold only in-flight work).

**Enable only after** `deployment:preflight` reports `[PASS] pg_dump: client
17, server 17`. On a 17 server, a 16 client makes every nightly run fail.

**How this relates to RDS automated backups.** RDS keeps daily snapshots and
transaction logs for point-in-time recovery within the retention window you
configure (confirm it is at least 7 days and that deletion protection is on).
That is the primary recovery path: minutes of data loss at worst. The nightly
dump is a second, independent, portable copy with up to a day of loss.

**Restore procedures**

1. *RDS point-in-time restore* (preferred): restore to a new instance from the
   RDS console, point `DB_HOST` at it, run `deployment:preflight`, deploy.
2. *Logical dump*: download the archive (admin backups screen), then into an
   isolated empty database — never over production in place:

   ```bash
   gunzip -c database_backup_YYYYMMDD_HHMMSS.sql.gz | psql "host=<target> dbname=<empty db> user=<role> sslmode=verify-full sslrootcert=/etc/ssl/rds/global-bundle.pem" -v ON_ERROR_STOP=1
   ```

   The dump carries `DROP … IF EXISTS` statements, so it must only ever be
   pointed at a throwaway or replacement database.
3. `bin/rails "backups:restore[<public_id>]"` exists but **refuses to run in a
   production process** and is meant for a recovery drill on a non-production
   host with `RESTORE_TARGET_DATABASE_URL`.

Rehearse option 2 once, on the test database, before real data exists.

## 7. Where Solid Queue runs (measured)

Requirement: queued **and** scheduled jobs must actually run on a 2 GiB host.
Measured locally in production mode against throwaway PostgreSQL 14 databases
(macOS 14, Ruby 3.4.7, Puma 8.0.2, 3 request threads, idle after boot, ~20 s).
macOS RSS counts shared copy-on-write pages once per process, so multi-process
numbers are an **upper bound**; Linux/EC2 must be re-measured (procedure below).

| Layout | Ruby processes | Summed RSS | Notes |
|---|---|---|---|
| Puma alone (no queue) | 1 | 138 MB | baseline |
| **Plugin, `async`** (`SOLID_QUEUE_IN_PUMA=1 SOLID_QUEUE_MODE=async`) | **1** | **139 MB** | worker, dispatcher, scheduler, supervisor are threads |
| Plugin, `fork` (the plugin default) | 5 | 433 MB | 138 + four children (60–81 each) |
| Puma + separate `bin/jobs`, `fork` | 1 + 4 | 138 + 241 = 379 MB | |
| Puma + separate `bin/jobs`, `async` | 1 + 1 | 138 + 139 = 277 MB | |

Execution check (`async`, plugin): the nightly `Backups::CreateDatabaseBackupJob`
enqueued through the production queue adapter ran within 3 s and produced a
`succeeded` backup row (30 KB); `deployment:queue_status` reported
`Dispatcher x1, Scheduler x1, Supervisor(async) x1, Worker x1`; and the
scheduler registered all four production recurring tasks
(`clear_solid_queue_finished_jobs`, `create_database_backup`,
`purge_expired_ai_call_transcripts`, `reconcile_stuck_ai_calls`). A
midnight-triggered run was not waited for; the recurring tasks are registered
from the same `config/recurring.yml` the supervisor loads.

**Recommendation.** Start with the plugin in `async` mode: one process, no
second supervisor tree. Trade-off to watch: jobs and requests then share one
Ruby GVL, so a CPU-heavy job (a 1,000-row candidate import, OCR) can slow API
responses, and a runaway job is only contained by the unit's `MemoryMax`.
If that shows up, move to the separate unit
(`deploy/systemd/descon-mps-jobs.service.alternative`, `PartOf` the API unit
so Capistrano's single permitted restart covers it). **Never run both**:
remove `SOLID_QUEUE_IN_PUMA` first.

`DB_POOL=10`: in `async` mode one process runs 3 request threads and 3 job
threads against the primary and queue databases; the pool must cover both. At
most ~25 connections per process against an RDS `db.t4g.micro`'s limit
(roughly 80–100 — check `SHOW max_connections`).

**Measure on the instance** (idle, then during a 1,000-row import):

```bash
systemd-cgls -u descon-mps-api.service
systemctl show descon-mps-api.service -p MemoryCurrent -p MemoryPeak
sudo smem -t -k -P 'puma|bin/jobs'      # PSS, not RSS (apt install smem)
```

## 8. Rehearsing locally

No server is touched. From a checkout with the `:deploy` gems installed:

```bash
deploy/test/with_env_test.sh                 # environment loader behaviour (14 checks)
deploy/rehearsal/run                         # Capistrano flow, rollback, lock (20 checks, ~3 min, needs rubygems.org)
deploy/test/nginx_routing_test.sh            # needs nginx on PATH (19 checks); also runs in CI
```

`deploy/rehearsal/run` executes the real `config/deploy.rb` against a
temporary directory with a fake rbenv, a fake `systemctl` and a fake health
probe, and asserts: first deploy, second deploy keeps the previous release, a
release that fails its health check restores exactly the previously serving
release and deletes the failed one, lock contention fails fast without
creating a release or releasing someone else's lock, a manual rollback, and a
normal deploy afterwards.

Rails-level checks need a production-shaped environment and were run
separately against throwaway local databases (see the PR description).

## 9. Integrations: honest state

* **SMS / candidate OTP.** `SMS_PROVIDER=test` sends nothing and does not
  return or log the code, so **no candidate can complete OTP login on a host
  using it**. `SMS_PROVIDER=sendpk` needs `sendpk.production.api_key` in
  encrypted credentials, an approved `SENDPK_SENDER_ID` and the approved
  `OTP_TEMPLATE_ID`/`OTP_TEMPLATE_ID_UR`. Real delivery from this host has
  **not** been verified. Staff email/password login works without SMS.
* **Email / SES.** Deferred. Staff invitations create the user and queue
  delivery, but there is no SMTP/SES configuration, so no invitation reaches
  anyone; create staff through the first-administrator procedure or add SES.
* **KuickPay payment codes (wallet / bank app).** The candidate can pay the fee by
  getting a code (KuickPay voucher number) in the app and paying it from JazzCash,
  Easypaisa or a bank app, as an alternative to the card checkout. It uses KuickPay's
  separate "Hybrid" API (Insert Voucher, Bill Payment Bulk Inquiry), which needs its
  own logins and the institution id (`KUICKPAY_INSTITUTION_ID`; falls back to
  `KUICKPAY_COMPANY_ID`). KuickPay issued a separate login for each call, so there are
  two pairs: `kuickpay.production.hybrid_username` / `hybrid_password` to create a
  voucher and `payment_status_username` / `payment_status_password` to check payments (the voucher
  login is refused by the payment-status call, so there is no fallback). Both pairs are required: the
  codes stay off if either is missing, so no code is issued that could not be seen as paid.
  Off until `KUICKPAY_VOUCHER_ENABLED=true`.
  * Opening the code tab creates one code for the fee (`POST /api/v1/candidate/payment/voucher`),
    valid `PAYMENT_VOUCHER_VALID_DAYS` days (14). No late fee: the due date is the expiry.
  * The candidate can have a code and a card checkout open at the same time and
    chooses which to pay; the screen tells them to pay only one. If both get paid, the
    nightly reconciliation flags `duplicate_fee_payment` on both payments, and finance
    refunds one outside the system and records a note on the finding.
  * KuickPay never calls us. The job `poll_kuickpay_vouchers` (every 5 minutes, in
    `config/recurring.yml`) asks KuickPay which codes were paid today and yesterday
    and marks them paid; the candidate then moves to Fee Paid like a card payment. A code
    counts as paid as soon as KuickPay lists it, before KuickPay settles the money to
    Descon (`isSettled` turns true about a working day later). A payment with the wrong
    amount is logged and left unpaid for finance. An unpaid code is closed a day after it
    expires.
  * The fee must be a whole number of rupees (KuickPay takes integers).
  * KuickPay's own fee (a flat 50 PKR per payment in its UAT) comes out of the amount
    paid, so Descon receives the fee minus that. The admin sets the fee including it;
    the admin fee screen says so.
  * UAT confirmed (27 Oct 2026): a paid code appears in the inquiry at once, unsettled.
    The SMS to the candidate is still to be confirmed with KuickPay.
* **KuickPay.** The hosted-checkout adapter (create session, redirect, signed
  return, status check) is implemented and was exercised against KuickPay's
  sandbox from a developer machine through a tunnel. `KUICKPAY_ENABLED=false`
  here: no production credentials, the return URL and this host's Elastic IP
  are not registered with KuickPay, and nothing has run from this host. Treat
  payments as **not ready** until a sandbox round trip is run from the
  deployed host over trusted HTTPS.
* **OCR.** `DOCUMENT_OCR_ENABLED=false`; the adapter uses Textract
  `AnalyzeDocument` Queries (issue/expiry date), because `AnalyzeID` only
  supports US documents and cannot read a Pakistani CNIC. Queries read a real
  CNIC correctly in the console; passport quality must still be tested with
  real samples. Extraction runs once, in a background job right after the
  upload, and the result is stored in `document_extractions`; HR's screen reads
  that stored row and never calls Textract. Textract's synchronous mode reads
  one page per PDF, so `DocumentOcr::PdfPageSplitter` cuts the first two pages
  of a multi-page PDF, and `DocumentOcr::DateExtractor` tries the front, then
  the back image or next page, stopping when both dates are found (at most 3
  Textract calls per document). Enabling it needs `textract:AnalyzeDocument` on the instance
  role (no resource-level scoping) and `DOCUMENT_OCR_ENABLED=true`.
* **Frontend mock-only screens.** The admin web app has prototype Hono routes
  (`src/app/api/**`, in-memory data) that no screen calls; see the
  `descon-fe` PR. Nothing here is "mock-only" at the API level.

## 10. Adding a domain later

1. DNS: `A` record for the new name to `52.221.51.231`.
2. Issue a normal certificate for the name (Certbot, `--webroot`, same
   webroot); the short-lived IP certificate can then be dropped.
3. `sudo ln -sfn /etc/letsencrypt/live/<name> /etc/nginx/tls/current` and
   `sudo systemctl reload nginx`. `server_name _` already matches any host.
4. `shared/.env`: change the host in `CORS_ALLOWED_ORIGINS` and
   `KUICKPAY_RETURN_URL`; restart the service.
   `action_mailer.default_url_options` becomes relevant only when emails carry
   links (they do not today).
5. Register the new return URL with KuickPay.
6. Rebuild and redeploy the frontend with `PUBLIC_ORIGIN=https://<name>`
   (the API base URL is baked in at build time, see the frontend PR).
7. Add `Strict-Transport-Security` to
   `deploy/nginx/descon-security-headers.conf` once renewals are ordinary.

SSH and the Capistrano `DEPLOY_HOST` keep using the Elastic IP; nothing in
deployment depends on the public hostname.

## 11. Continuous delivery (GitHub Actions + SSM)

CD does not use SSH (GitHub-hosted runners have no fixed IP and SSH is limited
to one address). **Actions → "Deploy backend" → Run workflow** lets you choose
what to deploy. To deploy a branch, pick it in the **Use workflow from** list (GitHub
lists the branches itself, so there is no name to type) and set `source` to `branch`;
the branch must contain this workflow file:

| `source` | What is deployed | Environment | Commit accepted by the instance |
|---|---|---|---|
| `main` (default) | the tip of `main` | `production` | only a commit already on `origin/main` |
| `branch` | the tip of the branch picked in **Use workflow from** (not `main`) | `preview` | any commit on a branch of this repository |
| `pull_request` + number | the head of that **open, same-repository** PR | `preview` | same as above |

A push to `main` runs the `main` path automatically (still behind the
`production` environment's approval).

For every run `.github/workflows/deploy.yml`:

1. **resolves** the selection to one commit SHA (a fork PR, a closed PR or an
   unknown branch fails here, and the SHA is printed in the run summary);
2. assumes the environment's AWS role through GitHub OIDC (no AWS key is stored
   in GitHub) and starts that environment's SSM document on the one instance.
   **No tests, lint or security scans run in this workflow**: CI already ran
   them on the pull request and on the push, and `main` should require CI as a
   status check so only tested code is deployed;
3. on the instance `/usr/local/sbin/descon-deploy-backend` checks the commit
   out in a tooling clone and runs the same `cap production deploy` an
   administrator runs, with Capistrano's local backend, so the shared lock,
   preflight, health gate and rollback apply unchanged. A failure leaves the
   previous release serving.

**Where the safety comes from.** Not from the workflow file — a branch can
edit it — but from three things a branch cannot change:

* **GitHub environments.** `production` is limited to the `main` branch and
  requires a reviewer. `preview` allows any branch but also requires a
  reviewer.
* **AWS roles.** Each environment assumes its own role, and the trust policy
  pins the OIDC `sub` claim to that environment, so a workflow run from a
  feature branch cannot obtain the production role.
* **SSM documents.** The production role may start only `DesconDeployBackend`,
  whose command is fixed and only accepts a commit on `origin/main`. The
  preview role may start only `DesconDeployBackendPreview`, whose command adds
  `--any-pushed-commit`. Each takes a single parameter validated as a 40-hex
  SHA, so neither role can run an arbitrary command.

**Be clear about what a preview deploy is.** It runs the branch's own code —
including its `deploy/` Capistrano configuration, migrations and Rails code —
on the instance, as the `deploy` user, against this host's real database and
S3 bucket. Anyone who can approve the `preview` environment can therefore run
code that someone with write access pushed. That is the intended trade for a
test host; do not point `preview` at a host holding real candidate data until
you have decided that is acceptable. Pull requests from forks are never
deployed (the workflow refuses them and the instance only fetches branches of
this repository).

One-time setup (**none of it has been done or exercised**):

1. IAM: create the GitHub OIDC provider
   (`token.actions.githubusercontent.com`, audience `sts.amazonaws.com`) and
   two roles:
   * `descon-be-deploy-production`: trust
     `deploy/aws/github-oidc-trust-policy-production.json`, permissions
     `deploy/aws/github-deploy-role-production-permissions.json`;
   * `descon-be-deploy-preview`: trust
     `deploy/aws/github-oidc-trust-policy-preview.json`, permissions
     `deploy/aws/github-deploy-role-preview-permissions.json`.
2. Systems Manager: create both documents
   (`aws ssm create-document --name <name> --document-type Command
   --document-format JSON --content file://deploy/aws/ssm-document-<name>.json`):
   `DesconDeployBackend` and `DesconDeployBackendPreview`.
3. Instance: attach `AmazonSSMManagedInstanceCore` to its role (§3.7) and
   install the entry script root-owned and not writable by `deploy`:

   ```bash
   sudo install -o root -g root -m 0755 deploy/bin/descon-deploy-backend /usr/local/sbin/descon-deploy-backend
   ```

   The deploy user also needs the `:deploy` gems for its tooling clone:
   `bundler 4.0.0` is already installed in §3.1.
4. GitHub → Settings → **Environments**:
   * `production`: deployment branches = `main` only; required reviewer;
     variable `AWS_DEPLOY_ROLE_ARN` = the production role's ARN.
   * `preview`: deployment branches = all branches; required reviewer;
     variable `AWS_DEPLOY_ROLE_ARN` = the preview role's ARN.
   * Repository variable `EC2_INSTANCE_ID` = `i-0834da05a4ff8aefe`. If it or
     the selected environment's role ARN is absent, the deploy job fails with
     a configuration error; checks alone cannot make EC2 Deploy green.

`deploy/test/commit_policy_test.sh` (8 checks) exercises the script's own
commit-policy function against a throwaway origin: main-only accepts only
`origin/main`; `--any-pushed-commit` also accepts a branch-only commit; an
unpushed commit and an unknown SHA are refused under both.

## 12. Open decisions

* **Backup retention.** Nothing deletes old nightly archives. Choose a
  retention period (and whether a purge job or S3 object tagging is built).
* **Real malware scanner** (ClamAV, GuardDuty Malware Protection for S3, or a
  vendor) and whether staff should see a per-document scan outcome (§5).
* **Restricted database role** (§3.3.1): adopt before real data.
* **Email.** SES domain/identity, production access request, SMTP settings,
  and what invitation links should point to.
* **Which Textract/OCR product** and the permission set, after sample tests.
* **Monitoring.** Certificate expiry (6-day certificates), `FreeableMemory`
  on RDS, disk and journald size on the instance, failed backup rows.

## What is and is not verified

Run for this change (see the PR for exact commands and output):

* New specs (`Deployment::*`, rake tasks): pass; full suite 2011 examples,
  0 failures, 98.83% line coverage; RuboCop, Brakeman, bundle-audit,
  Zeitwerk and `openapi:validate` clean.
* `deploy/rehearsal/run`: 20/20 checks on macOS against a temporary directory.
* `deploy/test/with_env_test.sh`: 14/14 checks; `deploy/test/commit_policy_test.sh`:
  8/8 checks (which commits a deploy may take).
* `deploy/test/nginx_routing_test.sh`: 19/19 checks against nginx **1.31.6**
  built from source on macOS (Ubuntu 24.04 ships 1.24; the `listen … http2`
  form used here is valid on both, but 1.24 itself was not run). It found and
  fixed a real bug: `/assets/` lost to the static-file regex without `^~`.
* ShellCheck 0.11.0 clean on every script under `deploy/`.
* Production-mode boot, `db:prepare` (four databases, seeds), `deployment:preflight`,
  Puma with Solid Queue (all four layouts in §7) and a real queued job, on a
  local PostgreSQL 14 with local-disk storage.
* `visudo -cf` on the sudoers file; workflow files parse as YAML.

**Not run** because it needs the instance, AWS, GitHub settings or secrets:
the systemd unit under real systemd, Nginx on the real host and under
nginx 1.24, certificate issuance and renewal, RDS TLS with the
RDS bundle, S3 operations (`deployment:storage_round_trip` against the real
bucket), the OIDC/SSM delivery path, reboot recovery, rollback on the real
host, SMS, KuickPay and email delivery.


### Nginx access to releases under `/home/deploy`

The web release is under the deploy user’s home. Give Nginx (`www-data`) traverse access to the home directory and read access to the web releases only; keep the API shared secrets private:

```bash
sudo apt-get install -y acl
sudo -iu deploy install -d -m 0755 /home/deploy/descon-mps-web/releases
sudo setfacl -m u:www-data:--x /home/deploy
sudo setfacl -m u:www-data:rx,d:u:www-data:rx /home/deploy/descon-mps-web /home/deploy/descon-mps-web/releases
```

After the first web deployment, check `sudo -u www-data test -r /home/deploy/descon-mps-web/current/index.html`. Do not grant `www-data` access to `/home/deploy/descon-mps-api/shared` or its `.env`.
