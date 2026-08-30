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
| `99999-9999999-9` | -- | Deliberately **never** seeded, to exercise the "unknown CNIC" path -- returns the identical generic response as the two CNICs above. `/request` still creates a decoy challenge row and calls through the SMS adapter for it, so `/verify` can return `otp_expired`/`otp_max_attempts` for this CNIC exactly as it would for a real one -- see [Security: identity-enumeration resistance](#security-identity-enumeration-resistance). |

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
- Inactive candidates are handled through the same non-enumerating request path as unknown candidates, so `/request` never delivers a real OTP to an inactive record.

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
- `CANDIDATE_DOCUMENT_MAX_BYTES`
- `SEED_DEMO_DATA` -- set to `true` only in development when you want demo candidates and the demo administrator created by `db:seed`
- `OTP_CODE_LENGTH`
- `OTP_EXPIRY_SECONDS`
- `OTP_RESEND_COOLDOWN_SECONDS`
- `OTP_MAX_ATTEMPTS`
- `OTP_RATE_LIMIT_PER_MINUTE`
- `OTP_IDENTITY_RATE_LIMIT_PER_MINUTE`
- `CANDIDATE_IMPORT_MAX_BYTES`
- `CANDIDATE_IMPORT_MAX_ROWS`
- `SMS_PROVIDER` -- `test` is the only implementation available until a real vendor adapter is added (see `app/services/sms/`); never set to anything else in production until one exists
- `ACTIVE_STORAGE_SERVICE`
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

## Candidate registry and CSV import

Candidate registry data remains split by domain responsibility:

- `candidates` stores candidate identity, authentication fields, preferred language, candidate-level status, and active state
- `candidate_assignments` stores the current reference number and workflow-stage relationship

Admin import is exposed as `POST /api/v1/admin/candidate_imports`.

- Requires an authenticated active staff session with the active `manage_candidates` permission
- Accepts `multipart/form-data` with `candidate_import[file]`
- Normalizes CNIC and mobile values before validation and persistence
- Detects duplicate CNICs and reference numbers inside the CSV and against existing database records
- Never silently overwrites an existing candidate or assignment
- Supports safe client retries through `Idempotency-Key`
- Records a PII-safe audit event with only summary counts and the request ID

Required CSV headers:

- `full_name`
- `cnic`
- `mobile_number`
- `reference_number`
- `preferred_locale`
- `candidate_status`
- `workflow_stage_code`
- `country_code`
- `project_code`
- `craft_code`
- `active`

Example import:

```bash
curl -X POST http://localhost:3000/api/v1/admin/candidate_imports \
  -H "Authorization: Bearer <staff_token>" \
  -H "Idempotency-Key: candidate-import-20260826-001" \
  -F "candidate_import[file]=@/path/to/candidates.csv;type=text/csv"
```

Safe sample CSV:

```csv
full_name,cnic,mobile_number,reference_number,preferred_locale,candidate_status,workflow_stage_code,country_code,project_code,craft_code,active
Ahmed Ali,42101-1234567-1,+923001234567,DES-001001,en,registered,registered,qatar,qatar_infrastructure,electrician,true
Fatima Noor,42102-1234567-2,+923001234568,DES-001002,ur,registered,documents_pending,uae,qatar_energy,welder,false
```

## Candidate profile API

Candidate-facing endpoints remain isolated from staff APIs.

- `GET /api/v1/candidate/profile` requires a candidate JWT, not a staff JWT
- The authenticated candidate is derived only from the candidate session token; the client never supplies a candidate ID
- The response returns only safe fields needed by the candidate UI and future document ownership:
  - public candidate ID
  - full name
  - masked CNIC
  - reference number
  - preferred locale
  - candidate status
  - current workflow stage
  - active state

Staff tokens are rejected from candidate-only endpoints, and inactive candidates cannot initialize or restore an authenticated candidate session.

## Candidate required documents and uploads

Candidate document upload and submission APIs remain candidate-facing. Admin review is exposed separately through dedicated admin endpoints.

- `GET /api/v1/candidate/documents` returns the authenticated candidate's document checklist
- `POST /api/v1/candidate/documents` uploads or replaces one candidate-owned document through `multipart/form-data`
- `GET /api/v1/candidate/application_progress` returns the authenticated candidate's authoritative readiness summary
- `POST /api/v1/candidate/document_submissions` atomically submits current uploaded documents for review
- Candidate identity always comes from the candidate bearer token; the client never supplies a candidate ID
- Staff tokens are rejected from candidate-only document endpoints
- Files are attached through Active Storage and are treated as private application assets; the API never returns public URLs, storage keys, disk paths, or internal IDs

Checklist behavior:

- Requirements are resolved from the candidate's current assignment against `document_requirements`
- The current implementation prefers the most specific active requirement match across global, country, project, and craft scopes for each stable document-type code
- If no current document exists for a requirement, the API returns `status: missing`
- Uploaded documents expose only safe metadata: public document ID, original filename, detected content type, file size, and upload timestamp

Upload behavior:

- Requires `candidate_document[requirement_code]` and `candidate_document[file]`
- `candidate_document[issued_on]` is additionally required when `requirement_code=police_character`
- Supports PDF, JPEG, and PNG only
- Detects actual content type server-side instead of trusting the filename extension alone
- Enforces `CANDIDATE_DOCUMENT_MAX_BYTES`
- Rejects any client-supplied `candidate_document[expires_on]`; PCC expiry is always calculated server-side as `issued_on.advance(months: 6)`
- Supports safe retries with `Idempotency-Key`
- Reusing the same idempotency key with the same file and requirement replays the original success response
- For PCC uploads, reusing the same idempotency key with a different `issued_on` value returns `409 idempotency_conflict`
- The replay decision is scoped to the authenticated candidate subject, not to a specific bearer token, so the same candidate can safely retry after renewing their session
- Reusing the same key with different upload content returns `409 idempotency_conflict`
- Replacements are allowed only while the current document is still candidate-replaceable; verified or pending-review records cannot be replaced by the candidate
- Failed replacements preserve the previous current document because superseding and new-document persistence occur in one transaction
- PCC replacements create a new version with its own `issued_on` and derived `expires_on`; previous PCC versions retain their original dates
- Non-PCC uploads never persist PCC date fields

PCC compliance behavior:

- The seeded PCC requirement code is `police_character`
- PCC `issued_on` must be a valid ISO date (`YYYY-MM-DD`) and cannot be in the future relative to the application date
- PCC `expires_on` is always derived with six calendar months, not a fixed number of days
- The checklist and admin review detail responses expose PCC-only metadata: `issued_on`, `expires_on`, and `compliance_status`
- `compliance_status` is derived, not persisted, and is one of:
  - `current`
  - `near_expiry`
  - `expired`
- `near_expiry` uses the configurable `PCC_NEAR_EXPIRY_DAYS` warning window without changing the calculated expiry date
- Non-PCC document responses omit PCC-only metadata

Application progress behavior:

- Progress is derived only from the authenticated candidate and the current assignment
- The backend resolves the active document requirements and computes readiness server-side; the client does not submit document IDs or requirement lists
- `required_total` counts only active required requirements
- `missing` and `rejected` required documents block submission
- An expired required PCC also blocks submission with the stable blocker reason `expired`
- `uploaded`, `pending_review`, and `verified` count as provided for progress purposes
- An expired PCC still keeps its review status history; expiry compliance is exposed separately and does not silently convert the document to `rejected`
- `completion_percentage` is based on provided required documents and returns `0` when no required documents are configured
- `submission_state` is currently one of:
  - `no_assignment`
  - `no_requirements`
  - `incomplete`
  - `ready`
  - `submitted`
  - `partially_verified`
  - `verified`
  - `changes_required`
- Blocking requirement entries include a stable `requirement_code`, localized `name`, and untranslated `reason` code

Document submission behavior:

- `POST /api/v1/candidate/document_submissions` accepts no request body because the backend derives everything from the authenticated candidate and their current assignment
- Submission is allowed only when the candidate is active, has a current assignment, has at least one required document rule, has no missing required document, has no rejected required document, and still has at least one current required document in `uploaded`
- Optional documents do not block submission, but current optional uploads are submitted alongside required uploads when a valid submission occurs
- The submission transaction locks the current assignment, re-resolves requirements, locks current document rows, rechecks readiness, moves current `uploaded` documents to `under_verification`, persists immutable submission evidence, and records a PII-safe audit event
- If any step fails, document statuses remain unchanged and no submission success is stored for idempotent replay
- Reusing the same `Idempotency-Key` for the same authenticated candidate replays the original successful response even after session renewal because the fingerprint does not include the bearer token
- Reusing the same key while another request is still processing returns `409`, and reusing it for a different authenticated candidate remains isolated through subject scoping
- This ticket does not add an automatic workflow-stage transition because no explicit documented transition rule was found in the current repository requirements/proposal material

Localized upload error codes:

- `missing_file`
- `invalid_requirement`
- `unsupported_file_type`
- `file_too_large`
- `empty_file`
- `replacement_not_allowed`
- `inactive_account`
- `unauthorized`
- `idempotency_conflict`

Example checklist request:

```bash
curl \
  -H "Authorization: Bearer <candidate_access_token>" \
  -H "X-Locale: ur" \
  http://localhost:3000/api/v1/candidate/documents
```

Example upload request:

```bash
curl -X POST http://localhost:3000/api/v1/candidate/documents \
  -H "Authorization: Bearer <candidate_access_token>" \
  -H "X-Locale: en" \
  -H "Idempotency-Key: candidate-document-20260826-001" \
  -F "candidate_document[requirement_code]=police_character" \
  -F "candidate_document[issued_on]=2026-08-01" \
  -F "candidate_document[file]=@spec/fixtures/files/test.pdf;type=application/pdf"
```

Example application-progress request:

```bash
curl \
  -H "Authorization: Bearer <candidate_access_token>" \
  -H "X-Locale: ur" \
  http://localhost:3000/api/v1/candidate/application_progress
```

Example document-submission request:

```bash
curl -X POST http://localhost:3000/api/v1/candidate/document_submissions \
  -H "Authorization: Bearer <candidate_access_token>" \
  -H "X-Locale: en" \
  -H "Idempotency-Key: candidate-submission-20260826-001"
```

Production storage note:

- Production must set `ACTIVE_STORAGE_SERVICE` explicitly to an approved durable private storage backend before deploying candidate uploads
- The production environment no longer falls back to `local` storage for uploads
- Leaving `ACTIVE_STORAGE_SERVICE` unset in production now fails fast during boot instead of silently storing candidate documents on local disk

## Candidate bank details

Candidate bank-detail capture is isolated from the candidate-document checklist and future payment workflows.

- `GET /api/v1/candidate/bank_details` returns the authenticated candidate's current bank-detail submission state
- `PUT /api/v1/candidate/bank_details` creates or replaces the current bank detail and proof for the authenticated candidate
- `GET /api/v1/admin/candidates/:candidate_id/bank_details` returns the current bank detail for one candidate's current assignment
- `POST /api/v1/admin/candidates/:candidate_id/bank_details/proof_access` returns a short-lived private proof-access path

Candidate behavior:

- Candidate identity comes only from the candidate bearer token; staff tokens are rejected
- Active candidates may create or replace exactly one current bank-detail record for their current assignment
- The mutation is multipart and accepts `bank_detail[account_title]`, `bank_detail[account_number]`, `bank_detail[bank_name]`, and one mandatory `bank_detail[proof]`
- `Idempotency-Key` is supported for safe retry; replay is scoped to the authenticated candidate and the request fingerprint excludes the bearer token so retries still succeed after token renewal
- Reusing an idempotency key with a different payload returns `409 idempotency_conflict`
- Proof uploads reuse the existing private Active Storage validation rules: PDF, JPEG, and PNG only, non-empty file, and the configured `CANDIDATE_DOCUMENT_MAX_BYTES` maximum size
- Replacement is atomic: if validation, persistence, or audit creation fails, the previous current bank detail and proof remain in place and unattached new blobs are purged

Data protection:

- `account_title` and `account_number` are encrypted at rest with Rails Active Record encryption
- Production must provide `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`
- Candidate responses always return a masked account number with only the final four characters preserved
- Internal numeric IDs, encryption ciphertext, storage keys, disk paths, checksums, and proof contents are never returned
- Parameter filtering excludes bank-detail plaintext values and proof payloads from application logs

Staff authorization and access:

- Staff access uses the existing policy layer and backend-issued effective permissions
- Roles with active `view_payments` receive masked bank details
- Roles with active `manage_payments` may receive the unmasked account number and request proof access
- Candidate tokens are rejected from the admin banking endpoints
- The proof-access endpoint returns a short-lived private Active Storage proxy path, not a public URL
- Both the JSON proof-access response and the proxied proof response are returned with `Cache-Control: private, no-store`

Audit behavior:

- Audit events are recorded for initial bank-detail submission, replacement, unmasked staff reads, and proof access
- Audit metadata is limited to safe public identifiers, request ID, and timestamp context
- Audit records never include plaintext bank values, proof metadata beyond the current record, storage keys, checksums, or raw multipart payloads

Example candidate bank-detail submission:

```bash
curl -X PUT http://localhost:3000/api/v1/candidate/bank_details \
  -H "Authorization: Bearer <candidate_access_token>" \
  -H "X-Locale: en" \
  -H "Idempotency-Key: candidate-bank-detail-20260829-001" \
  -F "bank_detail[account_title]=Ahmed Ali" \
  -F "bank_detail[account_number]=PK24SCBL0000001123456702" \
  -F "bank_detail[bank_name]=Meezan Bank" \
  -F "bank_detail[proof]=@spec/fixtures/files/test.pdf;type=application/pdf"
```

Example staff bank-detail lookup:

```bash
curl \
  -H "Authorization: Bearer <staff_access_token>" \
  http://localhost:3000/api/v1/admin/candidates/<candidate_public_id>/bank_details
```

Example staff proof-access request:

```bash
curl -X POST \
  -H "Authorization: Bearer <staff_access_token>" \
  http://localhost:3000/api/v1/admin/candidates/<candidate_public_id>/bank_details/proof_access
```

## Admin document review and verification

Admin review is isolated from candidate-facing upload/submission APIs.

- `GET /api/v1/admin/document_submissions` returns the paginated review queue
- `GET /api/v1/admin/document_submissions/:id` returns one submission by submission public ID
- `POST /api/v1/admin/candidate_documents/:id/access` returns a short-lived private Active Storage proxy path for one submitted current document
- `POST /api/v1/admin/candidate_documents/:id/verifications` verifies one current pending-review document
- `POST /api/v1/admin/candidate_documents/:id/rejections` rejects one current pending-review document with a required reason

Authorization and scope rules:

- Every admin review endpoint requires an authenticated active staff session with the active `manage_candidate_documents` permission
- With the current seeded permission matrix, `admin`, `hr`, and `mps` may access the review queue and make review decisions; `finance` and `management` are denied by policy
- Candidate bearer tokens are rejected from every admin review endpoint
- Only current submitted documents are reviewable; unsent, superseded, or inaccessible documents return safe `404`/`403` responses through the standard API envelope

Queue and detail behavior:

- The queue supports `page[number]`, `page[size]`, and safe filters for `status`, `submitted_from`, `submitted_to`, `candidate_public_id`, `project_code`, and `country_code`
- Queue and detail responses expose public IDs only
- The API returns safe metadata only: candidate public ID and display name, assignment public ID and reference number, localized country/project/craft names, submission time, review counts, localized document-type names, file content type, file size, upload time, and review status
- The API does not expose internal numeric IDs, storage keys, disk paths, public file URLs, CNIC, passport details, phone numbers, or document contents

Review-state rules:

- `pending_review`: every required submitted document is still pending review
- `partially_reviewed`: at least one required submitted document is verified and at least one required submitted document is still pending review
- `changes_required`: at least one required submitted document is rejected
- `verified`: every required submitted document is verified

Secure document access behavior:

- Access is granted only through an authorized backend endpoint and returns a short-lived private proxy path, not a permanent URL
- `ADMIN_DOCUMENT_ACCESS_TTL_SECONDS` controls the expiry window and defaults to `300`
- Both the JSON access response and the proxied document response set `Cache-Control: private, no-store`
- Every successful document-access action records a PII-safe audit event

Verification and rejection behavior:

- Only a current `under_verification` document may be reviewed
- Verification sets the document to `verified`, records the reviewer and decision timestamp, and clears any stale rejection reason
- Rejection requires a plain-text reason, trims surrounding whitespace, rejects HTML content, records the reviewer and decision timestamp, and sets the document to `rejected`
- Rejected candidate documents become replaceable again through the existing candidate upload flow because candidate replacement rules already allow replacement for current `rejected` documents
- Verification and rejection are atomic: the document lock, status update, reviewer/timestamp changes, and audit event are persisted together or not at all

Idempotency and concurrency:

- Verification and rejection require `Idempotency-Key`; missing keys return `400 missing_idempotency_key` and malformed keys return `400 invalid_idempotency_key`
- Retrying the same successful decision with the same authenticated staff user and the same request fingerprint replays the original `201` response
- Reusing the same key for a different document, action, or rejection reason returns `409 idempotency_conflict`
- The fingerprint intentionally excludes the bearer token so a retried request still replays after staff session renewal
- Concurrent verify/reject attempts against the same current document are serialized by row locking so only one decision succeeds

Deployment/backfill:

- Existing `candidate_document_submissions` are backfilled into immutable `candidate_document_submission_items` during deployment so submissions created before the admin-review rollout remain reviewable

Audit and privacy:

- Audit events are recorded for successful document access, verification, and rejection
- Audit metadata is limited to safe identifiers such as staff public ID, candidate public ID, assignment public ID, submission public ID, document public ID, requirement code, request ID, and timestamp
- Audit metadata never includes document contents, CNIC, phone numbers, storage keys, checksums, access URLs, authentication tokens, or raw request payloads

Example review-queue request:

```bash
curl \
  -H "Authorization: Bearer <staff_access_token>" \
  -H "X-Locale: ur" \
  "http://localhost:3000/api/v1/admin/document_submissions?filter[status]=pending_review&page[number]=1&page[size]=20"
```

Example submission-detail request:

```bash
curl \
  -H "Authorization: Bearer <staff_access_token>" \
  http://localhost:3000/api/v1/admin/document_submissions/<submission_public_id>
```

Example secure-document-access request:

```bash
curl -X POST http://localhost:3000/api/v1/admin/candidate_documents/<document_public_id>/access \
  -H "Authorization: Bearer <staff_access_token>"
```

Example verify request:

```bash
curl -X POST http://localhost:3000/api/v1/admin/candidate_documents/<document_public_id>/verifications \
  -H "Authorization: Bearer <staff_access_token>" \
  -H "Idempotency-Key: review-verify-20260827-001"
```

Example rejection request:

```bash
curl -X POST http://localhost:3000/api/v1/admin/candidate_documents/<document_public_id>/rejections \
  -H "Authorization: Bearer <staff_access_token>" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: review-reject-20260827-001" \
  -d '{
    "rejection": {
      "reason": "Document is unreadable."
    }
  }'
```

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
- `GET /api/v1/candidate/documents`
- `POST /api/v1/candidate/documents`
- `GET /api/v1/candidate/application_progress`
- `POST /api/v1/candidate/document_submissions`
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
- `POST /api/v1/candidate/documents` accepts multipart uploads with `candidate_document[requirement_code]` and `candidate_document[file]`, validates actual content type, and stores files privately
- `POST /api/v1/candidate/documents` additionally requires `candidate_document[issued_on]` for `police_character`, rejects client-supplied `candidate_document[expires_on]`, and derives `expires_on` with `issued_on.advance(months: 6)`
- `POST /api/v1/candidate/documents` supports replay-safe retries with `Idempotency-Key` and returns `409 idempotency_conflict` when a key is reused for different upload content
- `GET /api/v1/candidate/application_progress` returns localized workflow-stage and blocking-requirement names while preserving stable machine-readable state and reason codes; an expired required PCC blocks submission with blocker reason `expired`
- `POST /api/v1/candidate/document_submissions` is a bodyless candidate-authenticated mutation that atomically moves current `uploaded` documents to `under_verification`, records immutable submission evidence, and returns blocking requirement details on `422`

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
