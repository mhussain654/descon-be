# Core Relational Schema

## Key decisions

- `users` remains the staff-authentication table. Staff authorization is normalized through `roles`, `permissions`, and `role_permissions`, while `users.role` now references `roles.code`.
- The baseline least-privilege roles are `admin`, `hr`, `mps`, `finance`, and `management`. Their seeded permissions are intentionally scoped by operational responsibility.
- System-defined labels for roles, permissions, and workflow stages are resolved from Rails I18n in `config/locales/en.yml` and `config/locales/ur.yml`, so the database stores only stable codes for those entities.
- The repository pattern remains bigint primary keys plus UUID-style `public_id` fields for external-facing business records, rather than UUID primary keys.
- Candidate login is modeled around a normalized canonical `cnic` field and a required stored `mobile_number`. No candidate password or self-service account schema was added.
- `passport_number` is optional and uniquely constrained only when present.
- Candidate progress is centered on `candidate_assignments`, which tie a candidate to a country, project, craft, and current workflow stage.
- `candidate_stage_histories` preserves timestamped workflow transitions with explicit `from_workflow_stage` and `to_workflow_stage` references instead of inferring the prior state from event order.
- QVC tracking is stored on `candidate_assignments` as `qvc_outcome_code` and `qvc_outcome_date`. No automatic workflow branching is encoded in the schema.
- `document_requirements` supports future country-, project-, and craft-specific document rules without JSON columns.
- `audit_events` and `candidate_stage_histories` are immutable from normal application flows.
- `candidate_documents` tie verification metadata and rejection reasons directly to `status_code` through both model validations and database check constraints.

## Deletion and retention

- Reference data such as roles, permissions, workflow stages, countries, projects, crafts, and document types is retained and protected by restrictive associations.
- Core operational records use restrictive deletion behavior by default so workflow, payment, communication, and document history is preserved.
- Actor references on documents, payments, communications, and audit/stage history are nullable to allow staff-user deactivation or cleanup without erasing business history.
- Workflow definitions are system-defined and protected from unrestricted mutation in the model layer.

## Intentional extensions

- The written requirements define the canonical 15 workflow stages, so those are seeded as baseline data.
- The ticket does not define a closed permission catalog or a closed QVC/payment outcome taxonomy. The schema therefore stores machine-readable codes and seeds only the minimum baseline role/permission set needed for staff administration.
- The canonical CNIC storage format is `#####-#######-#`, which preserves a straightforward migration path to future encryption plus blind-index lookup.
