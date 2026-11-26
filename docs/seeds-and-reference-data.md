# Seeds and reference data

## When seeds run

- **Deploys do not run the seeds on an existing database.** The deploy runs
  `rake db:prepare` (`lib/capistrano/tasks/release.rake`, task
  `deploy:db_prepare`). `db:prepare` runs pending migrations every deploy, but
  loads `db/seeds.rb` **only when it creates a new, empty database**.
- After that, seeds run only when someone runs them on purpose:

  ```bash
  bin/rails db:seed
  ```

  On the server, with the usual prefix from the deployment runbook:
  `$RUN rails db:seed`.

To make a deploy run the seeds every time (not recommended), add a step after
`deploy:db_prepare` in `lib/capistrano/tasks/release.rake` that executes
`rake db:seed`. To stop seeding even a new database, replace `db:prepare` with
`db:create db:migrate` in that task. Commit either change like any other code
change.

## Seeds only add what is missing

Developers manage reference data in admin (**Settings → Reference data**,
developer-only permission `manage_reference_data`). So the seeds never
overwrite a row that exists:

| Data | What the seed does |
| --- | --- |
| Countries, projects, crafts | Adds a missing code; never changes names or active state |
| Document types and checklists | Adds missing document types and requirement rows; never changes existing ones (developer edits stay). Codes listed as retired in `DocumentChecklists::Definitions` are deactivated |
| Role permissions | Gives a role its default permissions only if it has none yet (a new database). Developer-only permissions are removed from every role but developer |
| Workflow stages | Keeps the stage catalog, positions and active flags in line with the code (stage codes are used throughout the code); stage display names set in admin are separate columns and are never touched |
| Roles, permissions, SMS templates, settings rows, call scripts | Added when missing |
| Store reviewer candidate | Added when missing (needs an active admin or developer) |

New permissions, and any change that must reach existing databases, ship as
**migrations** (for example `20261126120000_add_manage_reference_data_permission.rb`),
not as seed changes, because deploys run migrations but not seeds.
