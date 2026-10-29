# Candidate progress SMS

Candidates get an SMS only at the steps where they have to do something or
hear real news. Internal Descon steps (verification, e-number, visa case,
sharing with the Qatar BU, ...) send nothing.

The SMS go through send.pk, with the same endpoint, API key and sender as the
OTP. Each message has its own approved send.pk template, an English one and an
optional Urdu one, set as env vars `<MESSAGE>_TEMPLATE_ID` and
`<MESSAGE>_TEMPLATE_ID_UR` (read in `config/sendpk.yml`). The candidate's
`preferred_locale` picks the template; with no Urdu template the English one
is used. A message whose template is not set yet is not sent: its delivery is
recorded as `skipped` / `not_configured`, so templates can be added one by one.

Admins can switch all progress SMS, or single messages, off in **App Settings**
(`AppFeatureSetting`). A message switched off is recorded as `skipped` /
`disabled` and is never sent later, even when switched back on.

## Messages

| Message (`message_code`) | When | Countries | Template variables |
|---|---|---|---|
| `registered` | Candidate added and asked for documents (enters Documents Pending) | All | `name` |
| `document_rejected` | HR rejects a document | All | `name`, `document` (document name, in the candidate's language) |
| `medical_appointment` | Enters a medical appointment stage (Medical Pending, Medical Appointment, GAMCA Medical Pending) **with** an appointment date | All | `name`, `date` |
| `fee_pending` | Enters Fee Pending | All | `name`, `amount` (rupees) |
| `medical_unfit` | Medical result recorded as unfit | All | `name` |
| `qvc_appointment` | QVC appointment booked, including a follow-up after re-medical | Qatar | `name`, `date` |
| `visa_issued` | Visa issued, including a re-decision | All | `name` |
| `visa_rejected` | Visa rejected, including a re-decision | All | `name` |
| `protection_call` | Enters Protection Call with status "scheduled" | Qatar | `name`, `date` |
| `ticket_handover` | Enters Ticket Handover | All | `name`, `date` (handover date) |
| `flight_details` | Flight details added | Qatar | `name`, `airline`, `flight`, `sector`, `date`, `time` (Pakistan time) |

Dates are sent as `dd-mm-yyyy`. Every message also sends `name` (the
candidate's full name); a template may leave it out. In send.pk a variable is
written `#name#`, `#date#`, and so on. The suggested wording is in
`config/locales/en.yml` and `ur.yml` under `candidate_sms` (used only by the
test SMS provider; send.pk sends its own approved text).

Not sent: Protection Day (recorded after the candidate appeared) and a fit
medical result (the Fee Pending SMS follows instead).

## How it works

- `CandidateSms::StageMessage` picks the message when a candidate enters a
  stage (called from `CandidateWorkflows::TransitionSideEffectRecorder`).
  Document rejection, a QVC follow-up and a visa re-decision call
  `CandidateSms::ScheduleDelivery` directly.
- `CandidateSms::ScheduleDelivery` stores a `candidate_sms_deliveries` row and
  queues `CandidateSms::DeliveryJob`, inside the same transaction as the
  change. Its `dedupe_key` names the event (a stage entry, a QVC attempt, a
  visa decision, a document), so one event never sends twice.
- `CandidateSms::DeliveryJob` sends it through `Sms::SendMessage` right away,
  at any hour. A timeout or network error is retried up to 5 times, 5 minutes
  apart, then marked `failed`. The status is `sent`, `failed` or `skipped`.
