# Candidate progress SMS

Client decision (Nov 2026): only **three** SMS go out automatically -- all
documents submitted, visa issued and ticket ready for handover. Every other
message with a template id is sent only by hand: staff with the
`send_candidate_sms` permission pick it on the candidate page's **SMS** tab,
choose English or Urdu (the candidate's own language is preselected), fill in
any values it needs and send it. Manual SMS are recorded with the staff
member who sent them (`candidate_sms_deliveries.sent_by_id`).

The SMS go through send.pk, with the same endpoint and API key as the OTP.
The sender differs: the login code goes out from the short code
(`otp_sender_id` in `config/sendpk.yml`), every other SMS from the brand name
(`sms_sender_id`). Each message has its own approved send.pk template, an English one and an
optional Urdu one. A developer sets their ids in the web app under **App
Settings -> SMS settings** (the `sms_templates` table, one row per message,
the OTP included); a change takes effect on the next SMS with no deploy or
restart. The candidate's
`preferred_locale` picks the template; with no Urdu template the English one
is used. A message whose template is not set yet is not sent: its delivery is
recorded as `skipped` / `not_configured`, so templates can be added one by one.

All automatic SMS can be switched off together on the App Settings **Features**
tab (`AppFeatureSetting#progress_sms_enabled`), and single messages on the
**SMS settings** tab (`SmsTemplate#enabled`, shown as "Send automatically").
A message not sent automatically is recorded as `skipped` / `disabled` when
its step is reached and is never sent later, even when switched back on. Both
switches only affect automatic sending: staff can still send any message with
a template by hand. The OTP cannot be switched off: candidates could no longer log in.
Both tabs are developer-only (`manage_app_settings`) and every change is
audited.

## Messages

| Message (`message_code`) | When | Countries | Template variables |
|---|---|---|---|
| `otp` | Candidate asks for a login code | All | `code`, `minutes` (no `name`) |
| `registered` | Candidate added and asked for documents (enters Documents Pending) | All | none |
| `documents_submitted` | Candidate submits their documents for review (every submission) -- **automatic** | All | none |
| `document_rejected` | HR rejects a document | All | `name`, `document` (document name, in the candidate's language) |
| `medical_appointment` | Enters a medical appointment stage (Medical Pending, Medical Appointment, GAMCA Medical Pending) **with** an appointment date | All | `name`, `date` |
| `fee_pending` | Enters Fee Pending, **after** the candidate's KuickPay code is issued and KuickPay has texted it to them (see below) | All | none |
| `medical_unfit` | Medical result recorded as unfit | All | `name` |
| `qvc_appointment` | QVC appointment booked, including a follow-up after re-medical | Qatar | none |
| `visa_issued` | Visa issued, including a re-decision -- **automatic** | All | `country` (in the SMS's language) |
| `visa_rejected` | Visa rejected, including a re-decision | All | `name` |
| `protection_call` | Enters Protection Call with status "scheduled" | Qatar | `name`, `date` |
| `ticket_and_flight_details` | Enters Protection Day (candidate appeared for protection), the step before the ticket: asks them to check the app for ticket collection and flight details -- **automatic** | All | none |
| `ticket_handover` | Enters Ticket Handover -- **automatic** | All | none |
| `flight_details` | Flight details added | Qatar | `name`, `airline`, `flight`, `sector`, `date`, `time` (Pakistan time) |

Dates are sent as `dd-mm-yyyy`. Only the variables listed are sent to
send.pk (`SmsTemplate::VARIABLES`). In send.pk a variable is
written `#name#`, `#date#`, and so on. The suggested wording is in
`config/locales/en.yml` and `ur.yml` under `candidate_sms` (used only by the
test SMS provider; send.pk sends its own approved text).

### The fee stage and the KuickPay code

Entering Fee Pending queues `Payments::IssueFeeVoucherJob`. It issues the
candidate's KuickPay voucher (the candidate no longer has to press "Get code"
in the app: the payment screen shows the open code), asks KuickPay's
`sendSMS` to text that code, the fee and the due date to the candidate
(KuickPay does not text it by itself), and only then queues the
`fee_pending` SMS, whose approved text says the code has been sent. KuickPay's
SMS is sent once per voucher (recorded as a `voucher_sms_sent` payment
event). If KuickPay is down the job retries five times, five minutes apart;
after that no fee SMS goes out and the candidate can still get the code from
the app. Nothing happens when voucher payments are switched off or the
candidate can no longer pay. `sendSMS` is on KuickPay's live host
(`sms_base_url` in `config/kuickpay.yml`) and uses the voucher (Hybrid) login.

Not sent: a fit medical result (the Fee Pending SMS follows instead).

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
