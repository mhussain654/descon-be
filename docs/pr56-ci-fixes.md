# PR 56 CI fixes

Fee validation and conflict messages now live under api.errors in English and Urdu, matching the API error constructors. Their misplaced activemodel namespace previously raised missing-translation exceptions and returned 500 instead of the expected 422/409 responses. Request coverage includes Urdu validation and stale-edit responses.

OTP request specs assert the approved registration wording and absence of the submitted CNIC. Audit index specs clear persisted seed audit fixtures inside each rolled-back example transaction, preserving production audit behavior. MPS summary composition and spec formatting satisfy the existing RuboCop rules without exemptions. API shape and coverage thresholds are unchanged.

Validation: Ruby 3.4.7, RuboCop (1,051 files, no offenses), Zeitwerk, OpenAPI, Brakeman and updated Bundler Audit passed. Direct Rails checks confirmed the fee keys and validation/conflict errors in both languages. Focused request specs could not start because local PostgreSQL was unavailable. GitHub denied the tree write with Resource not accessible by integration, so remote CI has not verified this patch.

Apply in descon-be on docs-per-country at c277e55647980a1ce29aafd552d0e963631dbded, then run the CI workflow. Its coverage and security gates are unchanged.
