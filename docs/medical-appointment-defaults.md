# Medical appointment details and defaults

When staff move a candidate into a medical appointment stage (Medical Pending,
Medical Appointment, GAMCA Medical Pending), they can record where and when the
candidate goes for their medical:

| Field | Type | Example |
|---|---|---|
| `medical_center_name` | text | Al Shifa Medical Centre |
| `medical_center_address` | text | 12 Mall Road, Lahore |
| `medical_appointment_date` | date (YYYY-MM-DD) | 2026-11-20 |
| `medical_appointment_time` | time (HH:MM, 24-hour) | 09:30 |

All four are optional (as the date always was). They are sent as transition
evidence and saved on that move's stage history entry
(`candidate_stage_histories.metadata`), so they belong to that candidate.

## Defaults

Admin Settings → **Medical appointment** holds one default centre, address,
date and time (`MedicalAppointmentSetting`, `GET/PATCH
/api/v1/admin/medical_appointment_setting`, `manage_workflow` -- Admin and MPS).

- The move dialog opens with the defaults filled in (each allowed transition
  field carries a `default`); staff can change them for that candidate.
- What is sent with the move is what is saved. Changing the defaults later only
  affects candidates moved afterwards; a candidate already moved keeps their own
  details.
- Every change to the defaults is audited (`medical_appointment_setting_updated`).

## Where the candidate sees it

The mobile Status tab shows "Your medical appointment" under the Medical step:
the centre, address, date and time from their latest move into a medical
appointment stage (read from their workflow history).

The medical appointment SMS is unchanged: it still sends only `name` and `date`
(see `docs/candidate-sms.md`).
