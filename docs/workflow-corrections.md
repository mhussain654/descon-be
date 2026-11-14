# Correcting medical, QVC and flight details

Developers can correct a candidate's recorded medical appointment, QVC
appointment or flight from the candidate page's **Overview** tab. Candidates
ask for a change by calling; there is no request button in the app.

## Who

Only the developer role, through the developer-only permission
`correct_workflow_details` (migration `20261115070300` grants it to the
developer role on existing databases). Other roles don't see the boxes, and the
API refuses them with 403.

## When a box can be changed

| Box | Can change | Shown but disabled (`blocked_reason`) |
|---|---|---|
| Medical appointment (incl. KSA GAMCA) | once recorded | `past_medical`: medically fit, or moved beyond the medical stages. An unfit candidate held at the result stage can still be rebooked. |
| QVC appointment (Qatar) | once booked | `qvc_result_recorded`: the latest booking has a result or no-show |
| Flight details | once recorded | `mobilized` |

Nothing recorded yet → `not_recorded`.

## What a change does

- The candidate stays at the same stage.
- A reason is required (up to 500 characters).
- An AuditEvent records it (`medical_appointment_corrected`,
  `qvc_appointment_corrected` or `flight_detail_corrected`) with the old and new
  values. The box lists the latest changes.
- Unless "Send SMS to candidate" is unticked, the candidate gets
  `medical_appointment_changed`, `qvc_appointment_changed` or
  `flight_details_changed`. These need their send.pk template ids filled in under
  App Settings → SMS; until then they are recorded but not sent. The medical SMS
  is only sent when the appointment has a date.

## Where the values live

- **Medical**: stage history is append-only, so the corrected values are saved in
  `candidate_stage_history_corrections` (one row per history entry) and laid over
  the original details whenever history is read (`CandidateStageHistory#details`).
  The app reads history, so it shows the corrected values without a new build.
- **QVC**: the latest `candidate_qvc_attempts` row is updated.
- **Flight**: the `candidate_flight_details` row is updated. The departure is read as
  Pakistan time, and the ticket is optionally replaced.

## QVC appointment defaults

App Settings → **QVC appointment** (`manage_workflow`) holds the default centre,
address, date and time. The admin QVC booking form fills them in, and they can be
changed per candidate. A booking now also stores the centre, address and time. The
candidate app shows the latest booking on the Status tab (QVC Appointment step) and
Home while it is still to happen. This comes from `workflow.qvc_appointment` in
`/api/v1/candidate/application_progress`, and needs a new app build.
