# PR 58 review and CI repair

Reviewed original head: `22a5a39526f2d2781ccff603199c555589786ad1`.
Base: `docs-per-country-pr2` (`6ee3820f7532d02442b5fe8bf4180f8a7aaf9de9`).

## Resolved findings

- The three failing document-submission request examples were Bullet N+1
  failures. Updating each document invokes PCC validation, which reads its
  document type. Preload those types on the ready-to-submit records after
  readiness validation; retain Bullet enforcement and document validations.
  Blocked submissions do not load associations that they will not use.
- The Qatar BU prerequisite spec had no explicit document requirement and
  depended on seed data left by other examples. Create its requirement within
  the example so it consistently reaches the medical-fit gate.
- Medical and visa re-decisions bypassed the transition resolver's active
  candidate guard. Both now lock and validate the current candidate before
  resolving the current assignment from fresh database state.
- These services previously acquired the assignment lock before invoking a
  transition that locks the candidate first, creating an inverted lock order.
  Both now use candidate-first, assignment-second locking, consistent with
  normal transitions and QVC commands.
- Medical commands previously accepted a missing/blank expected stage even
  though OpenAPI requires it. Reject it before recording any result, using
  the existing localized validation message.
- Added service regression examples for deactivation, cached assignments and
  missing expected-stage protection. Existing failing request examples retain
  their N+1, idempotency and candidate isolation coverage.

## Review scope

Reviewed the PR's changed controllers, outcome persistence and serializers,
country prerequisites and evidence, upload validation/storage/scanner path,
PCC replacement policy, schema migration, OpenAPI changes, environment setup,
fixtures and regression tests. The visa-copy bypass through the generic JSON
transition endpoint is blocked by this PR. Scanner selection fails closed and
mock usage is explicitly limited to non-live deployments.

## Release dependencies and limits

- Production still needs a real malware scanner adapter. Only the mock adapter
  exists; production document uploads deliberately return 503 until a usable
  provider is integrated. This is a release dependency, not a reason to weaken
  scanning validation.
- Frontend follow-up is required for dedicated medical/visa re-decisions while
  held at an outcome stage and display of the new `outcomes` snapshot data.
  Forward-transition forms alone cannot complete those held workflows.
- This is a stacked PR targeting `docs-per-country-pr2`, not `main`.
- Rollback of the outcome migration after visa re-decisions exist requires data
  handling: those rows have a null history link, while the old schema requires
  one. Do not blindly roll back a deployed migration with live re-decision data.

## Verification

Local whitespace validation passes. Ruby and PostgreSQL are unavailable in
this workspace, and runtime installation is blocked; GitHub Actions is the
execution environment for RSpec, coverage, RuboCop, security, Zeitwerk and
OpenAPI verification. Confirm the final head's checks before merging.
