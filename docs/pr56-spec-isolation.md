# PR 56 remaining spec isolation fixes

The latest CI run (37212979400, head 89f76c0df01988e13f6f5a5e314ddaf87c3626b5) passes security, static analysis and integrity. Its four remaining failures are fixture-isolation issues.

The invitation acceptance service specs now use the suite's default per-example transactions. They have no concurrent connections and do not need nontransactional execution. Removing global User deletion avoids foreign-key violations from authentication events left by other nontransactional specs, and each invitation/audit fixture is rolled back naturally.

The logout replay spec checks the idempotency row for the current session and auth.logout scope rather than the global table count. It explicitly creates an unrelated idempotency row to prove other operations do not affect the assertion. Replay status, response equality and exact single-row enforcement remain covered.

RuboCop passes for all 1,051 files; git diff --check passes. Local PostgreSQL remains unavailable, so these request/service examples need the next CI run. No application behavior, schema, security or coverage thresholds change. Apply this incremental patch to descon-be on docs-per-country after the previous CI patch.
