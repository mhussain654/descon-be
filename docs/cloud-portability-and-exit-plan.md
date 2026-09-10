# Cloud portability and exit plan (MPS-911)

This document lists every AWS-specific dependency actually present in this codebase today
(confirmed by reading the code, not assumed), what moving each one to another provider or
on-premises would require, how to export the platform's data, and where operational ownership
sits at handover. It intentionally does not describe infrastructure that isn't built yet
(production deployment itself is tracked separately, outside this document's scope).

## What's actually AWS-specific today

| Dependency | Where it's used | How replaceable |
|---|---|---|
| **Amazon S3** (via Rails ActiveStorage) | Private file storage for candidate documents, bank proofs, flight tickets, and daily database backups (`config/storage.yml`'s `amazon:` service) | Low effort. ActiveStorage ships built-in services for Google Cloud Storage, Azure, and local disk, and a self-hosted S3-compatible store (e.g. MinIO) can usually be pointed at with the same `S3` service adapter by overriding the endpoint. No application code references S3 directly — every upload/download goes through ActiveStorage's own abstraction. |
| **AWS Textract** (`aws-sdk-textract` gem) | OCR extraction of passport/CNIC issue and expiry dates (`app/services/document_ocr/textract_adapter.rb`) | Contained. Isolated behind a single adapter class per this project's own provider-isolation convention (AGENTS.md: "application code must not directly depend on ... OCR ... APIs") — swapping providers means writing one new adapter class implementing the same `extract(bytes:)` interface, not touching any calling code. |

## What's referenced in requirements but not yet built

These are called out so they aren't mistaken for existing AWS lock-in:

- **Amazon SES** for outbound email — `config/environments/production.rb` only has commented-out
  generic SMTP scaffolding today (Rails' own template default). Whichever provider is chosen
  (SES or otherwise), Rails' ActionMailer is provider-agnostic at the SMTP/API level; there is
  no SES-specific code anywhere yet.
- Any AWS-specific compute/orchestration assumption (ECS, Lambda, EKS, etc.) — none exists.
  This is a plain Rails 8 app (Puma + Solid Queue/Cache/Cable, all backed by plain PostgreSQL)
  that runs the same way on any host that can run Ruby and Postgres.

## What's already provider-agnostic (no migration work needed)

- **Database**: plain PostgreSQL via the standard `pg` gem, configured entirely through generic
  `DB_HOST`/`DB_USERNAME`/`DB_PASSWORD`/`DB_PORT` environment variables (`config/database.yml`)
  — works identically against RDS, Aurora, Cloud SQL, a self-hosted instance, or any other
  Postgres-compatible service. Four logical databases (primary, Solid Queue, Solid Cache, Solid
  Cable) all use this same generic connection mechanism.
- **Background jobs**: Solid Queue (Rails 8's own default), not a cloud-specific queue service.
- **SMS**: SendPK (`app/services/sms/providers/sendpk_provider.rb`), a Pakistani SMS gateway —
  not an AWS service at all, already isolated behind `Sms::SendMessage`'s provider interface.
- **Payments**: KuickPay, isolated behind `Payments::Providers::*` adapters — not AWS.

## Data export procedure

- **Database**: the daily backup already produced by `Backups::CreateDatabaseBackupJob`
  (MPS-903) is a complete, plain-SQL `pg_dump` of the entire primary database — the same
  artifact doubles as the "export everything" mechanism for a migration or exit. Restore it
  into any PostgreSQL instance (any provider, or on-premises) via
  `bin/rails "backups:restore[<public_id>]"` (`app/services/backups/restore_database_backup_service.rb`),
  which only shells out to standard `psql` — nothing AWS-specific.
- **File storage**: every ActiveStorage attachment's blob can be listed and downloaded via
  standard Rails console/rake tooling (`ActiveStorage::Blob.find_each { |b| ... }`) regardless
  of which service backs it; migrating the files themselves to a new bucket/provider is a
  matter of re-uploading each blob's bytes to the new service and re-pointing
  `config/storage.yml`, not a data-format conversion.

## Ownership and handover

- The AWS account, S3 bucket(s), and Textract access used in production belong to whoever
  provisions them at deploy time (see the separate client credentials checklist) — this
  codebase has no hardcoded account/bucket identifiers; everything is environment-variable
  driven (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_S3_BUCKET`).
- Rotating away from AWS entirely requires no application code changes for storage (swap the
  `amazon:` service in `config/storage.yml` for another ActiveStorage service) and one new
  adapter class for OCR if Textract is dropped. Database and job infrastructure need no
  changes at all, since neither was ever AWS-specific.
