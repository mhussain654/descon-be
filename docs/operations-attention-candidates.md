# Operations attention candidates

GET /api/v1/admin/mps_dashboard now includes attention_candidates, a maximum of eight delayed non-terminal current assignments, oldest first with assignment ID as a stable tie-breaker. The existing view_mps_dashboard authorization and country/project/craft filters apply to the complete response, including these rows.

Each row contains candidate_full_name, candidate_public_id, reference_number, workflow_stage_code, days_waiting and severity (critical/delayed). There are no document URLs or contact/identity fields. Age uses the latest transition into the current workflow stage, falling back to assignment creation when there is no transition. The same non-terminal scope and configured thresholds used by delayed totals are reused; critical remains included in delayed.

This is an additive response extension with no migration or mutation. The frontend uses the rows for its bounded follow-up table. Old clients ignore the added field; the companion frontend explicitly handles an older API without rows.

RSpec/query/service/request tests and OpenAPI examples are updated. Ruby/Bundler are unavailable in the patch-producing workspace, so RSpec, RuboCop, Zeitwerk, Brakeman and Bundler audit must be run in the backend environment before deployment. OpenAPI YAML parsing and git diff checks are available locally.
