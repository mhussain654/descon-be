# Pre-launch data reset

A one-off cleanup that removes all test data before go-live, without losing
configuration. It deletes test data rather than dropping the database and
re-seeding, because the seeds do not recreate staff accounts or anything
entered in the admin screens (SMS template ids, fees, support number,
appointment/flight/AI call settings, call scripts, robocall voices, training
videos).

Code: `Maintenance::PrelaunchDataReset` (`app/services/maintenance/`) and the
`prelaunch_reset:*` rake tasks (`lib/tasks/prelaunch_reset.rake`).

## What it does

**Deletes**

- Every candidate and everything attached: assignments, consents, bank
  details, documents and their files, document submissions and OCR results,
  payments, payment events and reconciliations, visa/medical/QVC/protection/
  flight records, stage and workflow history, sign-in codes, sessions.
- Activity: SMS deliveries, communications, AI calls and bulk call batches,
  candidate imports, idempotency keys, the whole audit log.
- The stored files of those records (documents, photos, cheques, tickets,
  boarding passes, visa copies) are removed from S3/disk after the database
  part commits. A file still used by a kept record is never removed.
- Every staff account except the `developer` role, and every staff sign-in
  session and sign-in event (developers sign in again).
- Every campaign made while testing. The built-in **Test campaign** stays (the
  store reviewer lives in it); staff whose running campaign was removed fall
  back to all campaigns.

**Keeps**

- Roles, permissions (and what each role has), countries, projects, crafts,
  workflow stages (and any custom stage names), mobilization processes,
  document types and requirements, the Test campaign. Changes made in
  **Reference data** stay.
- Every admin setting, SMS templates, workflow stage call scripts, robocall
  voices, training videos (and their files), database backups.
- Developer accounts. Kept rows that named a removed staff member (for example
  a setting's "updated by") now name the earliest active developer.

**Safety**

- `prelaunch_reset:preview` only counts; it changes nothing.
- `prelaunch_reset:run` needs `CONFIRM=DELETE-ALL-TEST-DATA` and refuses when
  no active developer account exists.
- All database deletes run in one transaction: if any step fails, nothing is
  deleted.
- The delete order comes from the database's foreign keys. The spec fails if a
  new table belongs to a candidate but is not in the purge list, or if a kept
  table points at a purged one, so a future table always gets a decision.

Afterwards `db:seed` recreates the Google Play / App Store reviewer candidate
(it accepts a developer as the creator). It needs the `store_review` settings
in the encrypted credentials: production has them; a local database without
them skips this step, which is expected. The seed only adds what is missing
and never overwrites reference data (see `docs/seeds-and-reference-data.md`).

## Checklist

Local and production follow the same order; the sections below give the exact
commands.

1. Deploy the release (production) or pull the code and run
   `bin/rails db:migrate` (local).
2. Make sure an active developer account exists, and sign in with it once.
3. Stop the app (production only).
4. Take a fresh backup and check it says `succeeded`.
5. Preview, and check the numbers.
6. Run the cleanup, then `db:seed`.
7. Discard failed background jobs.
8. Start the app (production only).
9. Sign in again as the developer (the cleanup signs everyone out) and check
   every admin page (list in step 6 of the local rehearsal).
10. Production: check the store reviewer in the mobile app, then create the
    real staff accounts.

**Last local rehearsal:** 2026-11-26. Every admin page loaded without errors
afterwards, with empty lists and unchanged settings. Backup succeeded; the cleanup removed 43
candidates and their records, 363 stored files, 10 staff accounts and 1 test
campaign, and discarded 5 failed jobs. Kept: the developer account, 7
countries, 3 projects, 20 crafts, 13 document types and checklist rows, 5
active processes, 17 SMS templates, the Test campaign and the backups. The
store reviewer was skipped locally (no `store_review` credentials), as
expected.

## 1. Local rehearsal

Backend and frontend running locally (Rails API, web admin, mobile on the
emulator).

1. Make sure a developer account exists locally (the run refuses otherwise):

   ```bash
   cd descon-be
   read -rs DEV_PASSWORD && export DEV_PASSWORD
   bin/rails runner "User.create!(email: 'developer@descon.local', password: ENV.fetch('DEV_PASSWORD'), role: 'developer', active: true)"
   unset DEV_PASSWORD
   ```

2. Optional, for a fuller rehearsal: `bin/rails dev_data:seed_qa_data`.
3. Take a backup, the same way as production (it must print `succeeded`):

   ```bash
   bin/rails runner "Backups::CreateDatabaseBackupJob.perform_now(Date.current.iso8601, force: true); b = SystemDatabaseBackup.order(:created_at).last; puts [b.public_id, b.status_code].join(' ')"
   ```

4. Preview, then check the counts look right:

   ```bash
   bin/rails prelaunch_reset:preview
   ```

5. Run it, seed, and discard failed jobs:

   ```bash
   bin/rails prelaunch_reset:run CONFIRM=DELETE-ALL-TEST-DATA
   bin/rails db:seed
   bin/rails runner "SolidQueue::FailedExecution.discard_all_in_batches"
   ```

6. Sign in again as the developer and check every admin page:
   - Dashboards (management, admin, operations): load with zero counts.
   - Candidates, Mobilization, Document reviews, Finance payments,
     Communications, Bulk calls, Audit log: empty (the store reviewer appears
     under Candidates on production).
   - Reports: run with no rows.
   - Users: only developer accounts.
   - Settings (fees, support number, SMS templates, call scripts, robocall
     voices, appointment/flight/AI call settings, app settings, training):
     unchanged.
   - Reference data: countries, projects, crafts, role permissions,
     checklists and stage names unchanged.
   - Header campaign switch: only the Test campaign and "All campaigns".
   - Job logs and Backups: load; the backup from step 3 is listed. Job logs
     still list job runs from testing: they live in the job queue database,
     which the cleanup does not touch, and the recurring clean-up removes
     finished ones. To clear finished runs now (optional):
     `bin/rails runner "SolidQueue::Job.clear_finished_in_batches"`.
   - Then create a candidate, upload a document and a photo, and send an SMS.
   - Mobile (production): the store reviewer signs in and sees the Enrolled
     journey.

## 2. Production

Pick a quiet time (no staff working, before candidates are told about the
app). All commands run on the API server as `deploy`, in
`/home/deploy/descon-mps-api/current`, with the usual prefix:

```bash
sudo -iu deploy
cd /home/deploy/descon-mps-api/current
RUN="/home/deploy/descon-mps-api/shared/bin/with-env env RAILS_ENV=production RBENV_ROOT=$HOME/.rbenv RBENV_VERSION=3.4.13 PATH=$HOME/.rbenv/bin:$PATH rbenv exec bundle exec"
```

1. **Deploy** the release that contains this cleanup (and run its migrations,
   as every deploy does). Releases after 2026-11-26 add these migrations,
   which the deploy runs: `create_campaigns`,
   `add_campaign_to_candidate_import_batches`,
   `add_view_uploaded_documents_permission`,
   `add_manage_reference_data_permission`,
   `add_name_overrides_to_workflow_stages` (plus `add_email_to_candidates` and
   `retire_cheque_copy_document` if not deployed yet). Deploys do not run the
   seeds on an existing database.
2. **Confirm a developer account** exists and is active; sign in to the admin
   web with it once. If none exists, create one as in the runbook's "first
   administrator" step with `role: 'developer'`.
3. **Stop the app** so no staff or candidate writes data mid-run, and no
   background job runs:

   ```bash
   sudo -n /usr/bin/systemctl stop descon-mps-api.service
   ```

   (If `deploy` may only restart the service, ask the server admin to stop it.)

4. **Take a fresh backup** (`force: true` because the nightly one may already
   exist for today) and check it succeeded; note its id:

   ```bash
   $RUN rails runner "Backups::CreateDatabaseBackupJob.perform_now(Date.current.iso8601, force: true); b = SystemDatabaseBackup.order(:created_at).last; puts [b.public_id, b.status_code].join(' ')"
   ```

   It must print `succeeded`. Do not go on otherwise.

5. **Preview** and check the numbers (candidates, staff removed, developers
   kept, and the developer that kept settings will name):

   ```bash
   $RUN rails prelaunch_reset:preview
   ```

6. **Run** the cleanup, then seed:

   ```bash
   $RUN rails prelaunch_reset:run CONFIRM=DELETE-ALL-TEST-DATA
   $RUN rails db:seed
   ```

7. **Clear failed jobs** left by jobs that referred to deleted candidates (for
   example a queued SMS):

   ```bash
   $RUN rails runner "SolidQueue::FailedExecution.discard_all_in_batches"
   ```

8. **Start the app** and check it is healthy:

   ```bash
   sudo -n /usr/bin/systemctl start descon-mps-api.service
   ```

9. **Sign in again** as the developer (the cleanup signs everyone out) and
   **check** the same pages as in step 6 of the local rehearsal, the store
   reviewer in the mobile app, and one real flow (create a candidate, upload a
   document). Create that candidate in the Test campaign, so it stays out of
   the real campaigns' lists and reports.
10. **Recreate staff accounts** for the real users (admin, HR, MPS, finance,
    management) from the admin screen.

### If something goes wrong

- A failed run deletes nothing (one transaction); fix the cause and run again.
- To undo a completed run, restore the backup from step 4 with
  `backups:restore` into an isolated database and switch over (see
  `docs/deployment/aws-ec2-runbook.md`). Files already removed from S3 are only
  recoverable if bucket versioning is on.

### Notes

- KuickPay vouchers issued during testing but never paid: if one is paid
  after the cleanup, its payment notice no longer matches a payment and is
  refused (not found); no candidate is affected.
- Old daily backups still contain the test data; the daily prune job removes
  them over the next weeks (14 daily + 6 monthly are kept).
