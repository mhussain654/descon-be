# Candidate fee controller coverage

Added request coverage for the candidate fee read endpoint: management can read the inherited default; administrators can read the override/version; staff without payment-view permission are denied without receiving fee data. Additional requests cover a missing current assignment and distinguish an omitted amount from explicitly removing an override.

These examples exercise CandidateFeesController.show and its validation guards without changing application behavior or the 90% per-file coverage threshold. RuboCop passes across 1,051 files and git diff --check passes. Local request execution remains blocked by unavailable PostgreSQL; the next full CI run must confirm the final coverage percentage.

Apply this incremental backend patch to docs-per-country at aba27b87c6671c8983add9385d29a31632022b0f, after the prior CI fixes.
