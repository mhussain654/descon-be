# Descon Backend Engineering Instructions

## Scope and precedence

These instructions apply to the entire `descon-be` repository. Follow the
requirements and acceptance criteria of the active ticket together with this
file. If a ticket conflicts with these instructions, stop and request a clear
technical decision before implementing the conflicting requirement.

The application is a Rails API for a security-sensitive manpower recruitment
platform. Security, correctness, maintainability, extensibility and performance
are required parts of every change, not optional follow-up work.

## Working rules

- Read the active Trello ticket and related requirements before changing code.
- Keep each change limited to one ticket unless an approved dependency requires
  a small related change.
- Inspect existing patterns before introducing a new abstraction, gem or folder.
- Preserve unrelated user changes in the working tree.
- Do not commit secrets, generated credentials, local databases, logs or `.env`
  files containing real values.
- Do not leave commented-out code, debugging statements, temporary endpoints or
  unexplained TODOs.
- Update documentation, OpenAPI and tests in the same PR as the behavior change.

## Rails architecture

- Prefer Rails conventions and simple object-oriented design.
- Keep controllers thin. Controllers may authenticate, authorize, validate
  parameters, invoke application/domain behavior and render a response.
- Do not place business workflows, complex queries or provider logic in
  controllers.
- Keep models focused on persistence, associations, validations and cohesive
  domain behavior. Avoid oversized models and callback-driven workflows.
- Use service objects for multi-step business operations, external side effects
  or transactions that do not fit naturally in one model.
- Use query objects for complex filtering, searching, reporting, aggregation or
  reusable Active Record queries.
- Use policy objects for authorization.
- Use jobs for slow, retryable or external operations such as SMS, OCR, reports,
  imports, notifications and provider callbacks.
- Isolate external systems behind provider adapters. Application code must not
  directly depend on SendPK, eOcean, KuickPay, OCR or other vendor-specific APIs.
- Do not create service objects, query objects, concerns, middleware or wrappers
  for simple CRUD merely to satisfy a folder structure. Every abstraction must
  remove real complexity or duplication.
- Prefer composition over deep inheritance.
- Avoid generic `Utils`, `Helpers`, `Manager`, `Processor` and `Handler` classes.
  Use names that describe the business responsibility.
- Avoid duplicate logic. Extract shared behavior only after the shared concept
  and its ownership are clear.
- Avoid inappropriate concerns and metaprogramming that hide control flow.

## API and routing

- All application APIs must be versioned under `/api/v1`.
- Use RESTful, resource-oriented routes and standard HTTP verbs.
- Prefer nested resources only when the child is truly scoped by its parent.
- Avoid action-style routes such as `/approve_candidate` when a resource or state
  transition can represent the operation clearly.
- Use consistent JSON response and error formats.
- Return appropriate HTTP status codes.
- Paginate collection endpoints and apply safe maximum page sizes.
- Validate and document filtering, sorting and search parameters.
- Maintain `openapi/openapi.yaml` for every endpoint and schema change.
- Include realistic request, success and error examples in OpenAPI.
- Validate that implementation and OpenAPI remain synchronized in CI.
- Do not expose internal exception messages, SQL details or stack traces.

## Data and Active Record

- Use PostgreSQL constraints in addition to Rails validations for invariants.
- Add foreign keys, null constraints, unique constraints and check constraints
  where the database can protect correctness.
- Add indexes based on actual access patterns. Explain non-obvious indexes.
- Use transactions for operations that must succeed or fail together.
- Lock records when concurrent updates could violate business rules.
- Avoid destructive or irreversible migrations when a safe staged migration is
  possible.
- Make migrations safe for production-sized tables.
- Never use unbounded `Model.all` processing for large datasets; batch work.
- Avoid loading unnecessary columns or associations.
- Use database enums or constrained values only with an explicit evolution plan.
- Store timestamps in UTC and localize them only at application boundaries.
- Treat CNIC, passport, contact, financial and recruitment data as sensitive.

## N+1 prevention and query performance

- Every collection endpoint must be reviewed for N+1 queries.
- Use `includes`, `preload` or `eager_load` deliberately based on query behavior.
- Use `strict_loading` for suitable models and request paths.
- Enable Bullet or equivalent N+1 detection in development and test.
- Configure test/CI behavior to fail when a newly introduced N+1 query is found.
- Add query-focused specs for complex query objects and important endpoints.
- Review SQL count and shape for dashboards, exports, filters and reports.
- Do not fix N+1 issues by eagerly loading large unused association graphs.
- Use caching only with explicit ownership, expiry and invalidation behavior.

## Background jobs and integrations

- Jobs must be idempotent or safely deduplicated.
- Configure bounded retries and distinguish retryable from permanent failures.
- Do not place secrets or unnecessary personal data in job arguments.
- Log provider request identifiers, not secret credentials or sensitive payloads.
- Define timeouts for every external network call.
- Handle provider errors, malformed responses, timeouts and duplicate callbacks.
- Verify signatures and authenticity of inbound webhooks.
- Make webhook processing idempotent.
- Persist delivery/processing state when required for audit and reporting.

## Security requirements

- Apply authentication and authorization independently. Authentication alone is
  not permission to access a resource.
- Use Pundit policies consistently for protected resources and operations.
- Scope database queries to the authorized user, role and organizational context.
- Prevent insecure direct object references.
- Use strong parameter allowlists.
- Normalize and validate CNIC and phone input at the boundary.
- Never reveal whether a CNIC or phone number exists through OTP responses.
- Rate-limit authentication, OTP, password, upload, search and sensitive
  endpoints as appropriate.
- OTP values must be random, short-lived, single-use and stored as a digest.
- Enforce resend cooldowns, attempt limits and challenge expiration.
- Rotate refresh tokens and detect refresh-token reuse.
- Revoke sessions safely on logout and security-sensitive account changes.
- Never log tokens, OTPs, credentials, complete CNICs, passport numbers, bank
  details or document contents.
- Mask sensitive identifiers in logs and responses where full values are not
  required.
- Validate file type, size, content and ownership for uploads.
- Store private files using non-public access and time-limited authorized URLs.
- Protect against mass assignment, injection, unsafe deserialization, SSRF,
  path traversal and malicious file uploads.
- Configure CORS using explicit trusted origins; never use an unrestricted
  production wildcard with credentials.
- Use secure headers and TLS in deployed environments.
- Keep dependencies patched and review security advisories.
- Record security-sensitive and administrative actions in an audit trail.

## Localization

- Support English (`en`) and Urdu (`ur`) API messages.
- Use I18n keys for user-facing response messages; do not hardcode them in
  controllers or services.
- Preserve the configured locale-resolution and fallback behavior.
- Add both English and Urdu translations for every new user-facing message.
- Do not place database-backed business content in static locale files.

## RSpec standards

- Every behavior change requires meaningful automated tests.
- Use request specs for API behavior and response contracts.
- Use model specs for validations, associations and cohesive domain behavior.
- Use service specs for business operations and failure handling.
- Use query specs for filters, joins, ordering, pagination and aggregation.
- Use policy specs for every authorization rule.
- Use job specs for enqueueing, execution, retries and idempotency.
- Use integration/contract specs for external adapters without calling live
  provider services in the normal test suite.
- Use `describe` to name the class, method, job or endpoint under test.
- Use `context` to describe conditions such as valid input, invalid input,
  unauthorized access and provider failure.
- Use `let`, `subject` and `before` only when they improve clarity and reduce
  meaningful repetition. Do not hide important setup behind excessive hooks.
- Use `expect` to test observable outcomes, not private implementation details.
- Include success, validation failure, authentication failure, authorization
  failure, edge cases and relevant concurrency/idempotency scenarios.
- Keep examples deterministic and independent of execution order.
- Avoid broad stubs such as `allow_any_instance_of`.
- Freeze or control time when testing expiry, scheduling and timestamps.
- Do not call real SMS, payment, OCR, email or cloud services from tests.
- Factories must be valid by default and traits must express intentional states.
- Do not reduce coverage thresholds, exclude application files or add meaningless
  tests merely to increase the percentage.

## Coverage requirements

- SimpleCov overall line coverage must remain at or above 95%.
- SimpleCov per-file line coverage should remain at or above 90% unless an
  explicitly documented exception is approved.
- Coverage must start before application code is loaded.
- CI must fail when the minimum coverage is not met.
- Critical authentication, authorization, payment, document and workflow code
  requires branch and failure-path coverage, not only happy-path execution.

Recommended enforcement:

```ruby
SimpleCov.minimum_coverage 95
SimpleCov.minimum_coverage_by_file 90
```

## Code quality

- All Ruby code must pass the repository RuboCop configuration.
- Do not disable RuboCop rules inline or globally without a documented reason.
- Keep methods, classes and modules cohesive and reasonably small.
- Prefer guard clauses when they improve readability.
- Use explicit domain names instead of abbreviations.
- Avoid boolean arguments that obscure call-site meaning.
- Avoid long parameter lists; use a clear value object only when justified.
- Handle expected failures explicitly and consistently.
- Do not rescue `StandardError` broadly unless re-raising or translating at an
  intentional application boundary.
- Do not use exceptions for normal branching.

## Required verification

Run the relevant subset during development and the full suite before opening a
PR:

```bash
bundle exec rails zeitwerk:check
bundle exec rspec
bundle exec rubocop
bin/brakeman --no-pager
bundle exec bundle-audit check --update
bundle exec rails openapi:validate
```

Also verify migrations and schema when database code changes:

```bash
RAILS_ENV=test bundle exec rails db:prepare
git diff --check
```

## Definition of done

A backend ticket is complete only when:

- Every acceptance criterion is implemented.
- Routes are RESTful and OpenAPI is current.
- Authorization and sensitive-data handling have been reviewed.
- N+1 and query-performance risks have been checked.
- Tests cover success, failure and authorization paths.
- SimpleCov remains at or above the required thresholds.
- RuboCop, RSpec, Brakeman, Bundler Audit, Zeitwerk and OpenAPI checks pass.
- Database migrations and indexes are production-safe.
- Documentation and environment examples are updated.
- No secrets, debug code, unrelated refactors or unexplained TODOs are included.
- The PR describes risks, test evidence, API changes and any deployment steps.
