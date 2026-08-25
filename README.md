# Descon Manpower API

Rails 8.1 API for the Descon Manpower application, based on the reusable Rails API foundation.

- Devise staff authentication
- Candidate CNIC + OTP authentication (SMS-delivered, provider-adapter based)
- JWT access tokens with rotating database-backed refresh tokens
- Pundit authorization
- Solid Queue, Solid Cache, Solid Cable
- RSpec, RuboCop, Brakeman, Bundler Audit, SimpleCov
- Docker and Docker Compose
- OpenAPI validation

## Docker development

```bash
docker compose up --build
```

The API is available at `http://localhost:3000` and the readiness endpoint is:

```bash
curl http://localhost:3000/api/v1/health/ready
```

Database preparation runs automatically when the API container starts.

## Native development

```bash
bundle install
cp .env.example .env
bundle exec rails db:prepare
bundle exec rails db:seed
bundle exec rails server
```

The API runs locally without Docker on Ruby `3.4.7`, Rails `8.1.3.1`, and PostgreSQL `14+`.

Before `db:prepare`, make sure PostgreSQL is running locally and that the `DB_*` credentials in `.env`
match a local role with permission to create databases.

If you want the full local setup without starting the server immediately:

```bash
bin/setup --skip-server
```

`db:seed` is required for baseline reference data such as the system roles (`admin`, `hr`, `mps`, `finance`, `management`), scoped permissions, the canonical workflow stages, and reference catalogs (countries, projects, crafts, document types). The seed file is idempotent and safe to rerun.

Demo candidates are separate, development-only, and opt-in:

```bash
SEED_DEMO_DATA=true bundle exec rails db:seed
```

## Demo/seed data for candidate OTP authentication (MPS-106)

`SEED_DEMO_DATA=true bundle exec rails db:seed` creates two demo candidates and reserves one CNIC that is deliberately never seeded, so every path of `POST /api/v1/candidate/auth/otp/request` and `POST /api/v1/candidate/auth/otp/verify` can be exercised end-to-end. Demo candidate creation is disabled outside development. All values are synthetic and match no real person.

| CNIC | Mobile | Behavior |
| --- | --- | --- |
| `11111-1111111-1` | `+923001234567` | Full success path -- a request actually creates a challenge and attempts SMS delivery, and the correct code verifies. |
| `22222-2222222-2` | `+920000000000` | Registered candidate whose mobile matches the test SMS provider's reserved "undeliverable" pattern (10+ trailing zeros) -- a request still returns the identical generic response and still creates a verifiable challenge, but the simulated SMS delivery fails internally. |
| `99999-9999999-9` | -- | Deliberately **never** seeded, to exercise the "unknown CNIC" path -- returns the identical generic response as the two CNICs above. `/request` still creates a real (decoy) challenge row and calls through the SMS adapter for it, so `/verify` can return `otp_expired`/`otp_max_attempts` for this CNIC exactly as it would for a real one -- see [Security: identity-enumeration resistance](#security-identity-enumeration-resistance). |

Because [`SMS_PROVIDER=test`](#environment-variables) never sends a real message, retrieve the actual code from the database or Rails console during local development, for example:

```bash
bundle exec rails runner "
  candidate = Candidate.find_by(cnic: '11111-1111111-1')
  result = CandidateOtpChallenge.generate_for(candidate:)
  puts result.fetch(:code)
"
```

## Security: identity-enumeration resistance

The candidate OTP endpoints never reveal, through response body or response timing, whether a submitted CNIC belongs to a real candidate:

- `POST /request` always creates a challenge row and always calls through the SMS adapter, whether the CNIC resolves to a real candidate or not. For an unknown CNIC this is a **decoy challenge** (`CandidateOtpChallenge` with no `candidate`, a random never-delivered code, and a call to the SMS adapter with a synthetic destination) so both the response body and response latency are identical to the real-candidate path.
- `POST /verify` looks up the latest challenge by CNIC, not by resolving a candidate first, so `otp_expired` and `otp_max_attempts` are reachable for a decoy challenge exactly as they are for a real one -- these codes do not imply the CNIC exists. A decoy challenge can never actually succeed (there is no candidate to log in as), so a lucky correct-code guess against a decoy still returns `otp_invalid`, not success.
- The one exception is a CNIC that has never had `/request` called for it at all (no challenge row exists, real or decoy) -- `/verify` returns `otp_invalid` there too, using a fixed-cost dummy bcrypt comparison so this path is not measurably faster than a real comparison.

## Environment variables

All supported environment variables are documented in `.env.example`.

Required for local development:

- `JWT_SECRET`

Commonly adjusted per machine or environment:

- `DB_HOST`
- `DB_PORT`
- `DB_USERNAME`
- `DB_PASSWORD`
- `DB_POOL`
- `DB_NAME`
- `CACHE_DB_NAME`
- `QUEUE_DB_NAME`
- `CABLE_DB_NAME`
- `TEST_DB_NAME`
- `TEST_CACHE_DB_NAME`
- `TEST_QUEUE_DB_NAME`
- `TEST_CABLE_DB_NAME`
- `DB_STATEMENT_TIMEOUT_MS`
- `DB_LOCK_TIMEOUT_MS`
- `CORS_ALLOWED_ORIGINS`
- `JWT_ISSUER`
- `JWT_AUDIENCE`
- `DEVISE_MAILER_SENDER`
- `INVITATION_TOKEN_SECRET`
- `APP_SUPPORTED_LOCALES`
- `MAX_REQUEST_BODY_SIZE_BYTES`
- `API_RATE_LIMIT_PER_MINUTE`
- `AUTH_RATE_LIMIT_PER_MINUTE`
- `AUTH_IDENTITY_RATE_LIMIT_PER_MINUTE`
- `AUTH_REFRESH_TOKEN_RATE_LIMIT_PER_MINUTE`
- `STAFF_INVITATION_ACCEPT_RATE_LIMIT_PER_MINUTE`
- `CANDIDATE_JWT_AUDIENCE`
- `CANDIDATE_ACCESS_TOKEN_TTL_MINUTES`
- `CANDIDATE_REFRESH_TOKEN_EXPIRY_DAYS`
- `SEED_DEMO_DATA` -- set to `true` only in development when you want demo candidates and the demo administrator created by `db:seed`
- `OTP_CODE_LENGTH`
- `OTP_EXPIRY_SECONDS`
- `OTP_RESEND_COOLDOWN_SECONDS`
- `OTP_MAX_ATTEMPTS`
- `OTP_RATE_LIMIT_PER_MINUTE`
- `OTP_IDENTITY_RATE_LIMIT_PER_MINUTE`
- `SMS_PROVIDER` -- `test` is the only implementation available until a real vendor adapter is added (see `app/services/sms/`); never set to anything else in production until one exists
- `FORCE_SSL`
- `RAILS_LOG_LEVEL`
- `JOB_CONCURRENCY`

## Quality

```bash
RAILS_ENV=test bundle exec rails db:prepare
bundle exec rails zeitwerk:check
bundle exec rspec
bundle exec rubocop
bin/brakeman --no-pager
bundle exec bundle-audit check --update
bundle exec rails openapi:validate
git diff --check
```

To run the same checks as CI in one command:

```bash
bin/ci
```

## Health checks

```bash
curl http://localhost:3000/api/v1/health/live
curl http://localhost:3000/api/v1/health/ready
```

- `/api/v1/health/live` verifies process/application liveness
- `/api/v1/health/ready` verifies required database dependencies for the current environment

## API Docs

This project includes both the raw OpenAPI spec and a browser-based Redoc page.

- Browser docs URL: `/api-docs`
- OpenAPI URL: `/openapi/openapi.yaml`
- OpenAPI source file: `openapi/openapi.yaml`
- Validation command: `bundle exec rails openapi:validate`

To share docs with API consumers, use one of these approaches:

- Share the Redoc page at `/api-docs`
- Share the raw OpenAPI document at `/openapi/openapi.yaml`
- Import `openapi/openapi.yaml` into Swagger UI, Postman, or Stoplight

## Staff authentication

Staff authentication is limited to administrator-managed accounts. There is no public signup flow.

- `POST /api/v1/auth/login` authenticates `admin`, `hr`, `mps`, `finance`, and `management` users by email and password
- `POST /api/v1/auth/refresh` rotates the database-backed refresh token on every successful use
- `DELETE /api/v1/auth/logout` revokes the current session and is safe to repeat
- `GET /api/v1/users/profile` returns the authenticated staff profile with trusted server-side role information
- `PATCH /api/v1/user_invitation` completes the password-setup flow for an invited staff account

Security behavior:

- Unknown email and wrong password return the same generic `401 unauthorized` response
- Inactive accounts return `403 inactive_account`
- Refresh-token reuse revokes the affected session and records a security event
- Login attempts are throttled per IP and normalized email
- Refresh attempts are throttled per IP and refresh-token digest
- Successful login, refresh, logout, failed login, and refresh-token reuse are persisted in `authentication_events`

## Staff authorization

Authentication and authorization are enforced separately.

- Staff API authorization is enforced server-side through Pundit policies
- Access is denied by default unless a policy explicitly grants it
- `GET /api/v1/users/profile` is available to any authenticated active staff session for its own profile
- `GET /api/v1/users`, `POST /api/v1/users`, and `PATCH /api/v1/users/:id` require the active `manage_staff_users` permission; with the seeded role matrix, this is currently granted to the `admin` role only
- Frontend route guards or hidden navigation are not treated as a security boundary

## Staff user administration

Staff-user administration uses the existing `/api/v1/users` resource and a dedicated invitation-acceptance resource.

- `GET /api/v1/users` returns the paginated staff directory
- `POST /api/v1/users` creates an invited staff user and queues invitation delivery
- `PATCH /api/v1/users/:id` updates only allowlisted staff fields: `role` and `staff_state`
- `PATCH /api/v1/user_invitation` accepts a single-use invitation token from the filtered request body and sets the initial password

Canonical staff states:

- `invited`
- `active`
- `suspended`

Security and lifecycle rules:

- Every administration endpoint requires an authenticated, active staff session with the active `manage_staff_users` permission
- Public UUIDs are exposed as `id`; internal numeric IDs, password digests, invitation digests, Devise lock fields, and session records are never returned
- Invitation tokens are generated securely, stored only as SHA-256 digests, expire after `72` hours, and are single-use
- Active invitation tokens are derived deterministically from a dedicated server-side secret plus stable invitation data, so duplicate jobs can reproduce the same active token without persisting plaintext in PostgreSQL, Solid Cache, job arguments, logs, or audit metadata
- Invitation acceptance tokens are submitted in the JSON body, not the URL path, to avoid leaking plaintext tokens through access logs and browser history
- Duplicate delivery jobs reuse the same still-valid invitation token instead of rotating it and invalidating an already delivered email
- Invitation acceptance is rate-limited by `STAFF_INVITATION_ACCEPT_RATE_LIMIT_PER_MINUTE`
- Role changes and suspensions revoke only the affected user's active staff sessions immediately
- A staff user cannot suspend their own account
- The final active administrator cannot be suspended or demoted; the invariant is enforced inside a transaction with row locking
- Audit events are recorded for staff invitation, activation, role change, suspension, and reactivation with request IDs and PII-safe before/after metadata

Example staff invitation:

```bash
curl -X POST http://localhost:3000/api/v1/users \
  -H "Authorization: Bearer <admin_token>" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: invite-staff-20260825-001" \
  -d '{
    "user": {
      "email": "invited.staff@example.com",
      "role": "hr"
    }
  }'
```

Example staff update:

```bash
curl -X PATCH http://localhost:3000/api/v1/users/<public_uuid> \
  -H "Authorization: Bearer <admin_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "role": "finance",
      "staff_state": "active"
    }
  }'
```

Example invitation acceptance:

```bash
curl -X PATCH http://localhost:3000/api/v1/user_invitation \
  -H "Content-Type: application/json" \
  -d '{
    "invitation": {
      "token": "<invitation_token>",
      "password": "Password123!",
      "password_confirmation": "Password123!"
    }
  }'
```

Example login:

```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -H "X-Locale: en" \
  -d '{
    "auth": {
      "email": "admin@example.com",
      "password": "Password123!"
    }
  }'
```

Example refresh:

```bash
curl -X POST http://localhost:3000/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{
    "auth": {
      "refresh_token": "<refresh_token>"
    }
  }'
```

## I18n

API message localization is enabled by default with English as the default locale and English fallbacks for missing keys.

- Supported locales are configured through `APP_SUPPORTED_LOCALES` and default to `en,ur`
- Locale resolution order is `X-Locale`, then `Accept-Language`, then default `en`
- Standard JSON API responses include `Content-Language` and `Vary: Accept-Language, X-Locale`
- Request locale switching is isolated per request with `I18n.with_locale`
- Test mode raises on missing translations

Examples:

```bash
curl -H "X-Locale: ur" http://localhost:3000/api/v1/health/live
curl -H "Accept-Language: ur-PK,ur;q=0.9,en;q=0.8" http://localhost:3000/api/v1/health/live
```

To add a new language:

1. Add the locale code to `APP_SUPPORTED_LOCALES`
2. Create `config/locales/api.<locale>.yml`
3. Add translated Devise or model-level keys if that project needs them

Database-backed translated content should stay out of static locale files. Store translated fields explicitly, for example `title_en` and `title_ur`, or use a translation layer such as Mobility only when the project actually needs database-level translated content.

## API

- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `DELETE /api/v1/auth/logout`
- `POST /api/v1/candidate/auth/otp/request`
- `POST /api/v1/candidate/auth/otp/verify`
- `GET /api/v1/users`
- `POST /api/v1/users`
- `PATCH /api/v1/users/:id`
- `GET /api/v1/users/profile`
- `PATCH /api/v1/user_invitation`
- `GET /api/v1/health/live`
- `GET /api/v1/health/ready`

## API conventions

- Successful single-resource responses use `{ data, meta, errors }`
- Collection responses use the same envelope and include `meta.pagination`
- All timestamps are ISO 8601 UTC
- Public identifiers are exposed as `id`; internal database IDs stay private
- Error codes are machine-readable and language-neutral; error messages are localized through Rails I18n
- Supported locales are only `en` and `ur`; unsupported locales fall back to the best supported locale to preserve compatibility
- Request IDs are returned in both `X-Request-Id` and the JSON envelope
- Filtering and sorting are allowlisted per endpoint and reject unsupported fields
- Malformed query values return field-addressable `400` errors instead of being silently coerced
- `DELETE /api/v1/auth/logout` supports optional `Idempotency-Key` replay protection
- `POST /api/v1/auth/login` returns a localized success message plus an access token, refresh token, public session ID, and trusted server-side role information
- `POST /api/v1/auth/refresh` rotates the refresh token on every success and returns a localized success message
- `POST /api/v1/auth/refresh` returns `invalid_refresh_token` for invalid, expired, or replayed refresh tokens and `session_revoked` when the session has already been revoked
- `DELETE /api/v1/auth/logout` is safe to repeat with the same bearer token and still returns `{ revoked: true }`
- Idempotency keys must match `^[A-Za-z0-9:_-]{1,128}$`, are scoped per operation and authenticated subject, and are retained for 12 hours
- `POST /api/v1/users` creates staff users in the `invited` state and returns only safe summary fields plus a localized success message
- `PATCH /api/v1/users/:id` only accepts allowlisted `role` and `staff_state` changes and revokes the target staff user's sessions immediately after role changes or suspension
- `PATCH /api/v1/user_invitation` activates an invited staff account, reads the invitation token from the filtered request body, stores only the token digest, and never returns the plaintext invitation token
- `POST /api/v1/candidate/auth/otp/request` always returns the identical response shape and content regardless of whether the CNIC is unknown, resolves to a candidate whose mobile is currently undeliverable, or resolves to a candidate a code was actually sent to -- never use this endpoint's response to infer whether a CNIC exists
- `POST /api/v1/candidate/auth/otp/verify` collapses unknown CNIC, no requested challenge, an already-used challenge, and an incorrect code into the identical `otp_invalid` error; `otp_expired` and `otp_max_attempts` are intentionally reachable for both real and decoy challenges, so they do not function as an existence oracle
- Both candidate OTP endpoints are rate-limited per IP and per (normalized) CNIC, independently of the per-challenge attempt limit enforced by `otp_max_attempts`
- Candidate access/refresh tokens use a distinct JWT audience (`CANDIDATE_JWT_AUDIENCE`) from staff tokens and are backed by separate `candidate_sessions`/`candidate_refresh_tokens` tables, so a candidate token can never be accepted as a staff one or vice versa

Example collection request:

```bash
curl \
  -H "Authorization: Bearer <token>" \
  "http://localhost:3000/api/v1/users?page[number]=1&page[size]=20&filter[role]=hr&filter[staff_state]=active&sort=email"
```

Example idempotent logout request:

```bash
curl -X DELETE \
  -H "Authorization: Bearer <token>" \
  -H "Idempotency-Key: logout-20260823-001" \
  http://localhost:3000/api/v1/auth/logout
```

## Schema Docs

- ERD: `docs/schema/core_relational_schema.mmd`
- Schema notes: `docs/schema/core_relational_schema.md`
