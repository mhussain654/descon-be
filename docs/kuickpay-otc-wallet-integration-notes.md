# KuickPay OTC/wallet integration — notes (pre-implementation)

Status: **not started**. This document captures what's been learned from KuickPay's
own docs and live testing so far, so implementation can start from a clear picture
instead of re-deriving it. Nothing here has been built yet — verify every detail
below against the live sandbox before coding against it.

## Context

The client currently runs OTC/wallet (Easypaisa, JazzCash, bank) payments entirely
manually: staff generate a consumer/voucher code on KuickPay's merchant portal,
share it with the candidate, the candidate pays against that code through their own
bank/wallet app, and staff later download a settlement report from the portal to
share with MPS management. The client wants this added into the app so a candidate
has both options at checkout: the existing hosted card checkout (`kuickpay_hosted_checkout_adapter.rb`,
already built) and this OTC/wallet flow (not built).

Three KuickPay documents have been reviewed so far, describing two structurally
different integration shapes — **do not conflate them**:

1. **`Kuickpay hosted checkout (new).pdf`** — the existing, already-implemented card
   checkout flow. Not relevant to OTC/wallet.
2. **`Kuickpay_BPS_Integration_Guide_v3.2.pdf`** — the "biller" model. **We** would
   have to host `BillInquiry`/`BillPayment` endpoints and KuickPay calls **into**
   our system live, during the candidate's actual payment attempt. Raised as an
   architectural concern (our system becomes a single point of failure / adds
   latency inside someone else's payment path, see this session's ngrok fragility
   as a live example of why that's risky) — a clarifying question was sent to
   KuickPay asking if an alternative exists.
3. **`Kuickpay Hybrid Integration.pdf`** (a.k.a. "Kuickpay Core API's RESTful Hybrid
   Model", v1.1) — **this is the model to build against.** It is the direct answer
   to the question raised about (2): we call out to KuickPay, KuickPay owns and
   validates the payment entirely on their side, and we only poll for status
   afterward. No live inbound call from KuickPay into our system during payment.

## The Hybrid model — three endpoints

Base URL (UAT): `https://uat-adminapi.kuickpay.com` (confirm the production host
separately — not stated in this doc).

Auth: every request carries `username`/`password` as **headers** (not query params,
not a signed payload like the hosted-checkout adapter uses) — a materially different
auth mechanism from the existing `KuickpayHostedCheckoutAdapter` (HTTP Basic Auth)
and from the BPS guide (HMAC-SHA256 signing). Confirm during implementation whether
this needs its own credential pair (`KUICKPAY_HYBRID_USERNAME`/`_PASSWORD`) separate
from `KUICKPAY_COMPANY_ID`/`KUICKPAY_SECURED_KEY`.

### 1. Insert Voucher — `POST {baseURL}/api/insertPPMVoucher`

We call this to generate a voucher/consumer number for a candidate's fee — this
replaces staff manually creating the code on KuickPay's portal.

Key request fields: `institutionID`, `registrationNumber` (our own bill/customer
reference — likely `payment.provider_order_id` or similar), up to 10
`headN`/`amountN` line-item pairs (`head1`/`amount1` mandatory — e.g.
`"Total Fee"` / `1000`), `totalAmount`, `dueDate`, `amountAfterDueDate` (late-fee
amount), `expiryDate`, `issueDate`, `voucherMonth`, `voucherYear`, `name`, `mobile`,
`email`, `branch` (optional).

Response (success): `response_Code: "00"`, `response_description` = the actual
payable voucher/consumer number (e.g. `"0000832249220"`), `response_detail` =
KuickPay's own internal system voucher number.

This is the number we'd show the candidate in-app (and presumably still send via
SMS, matching how OTP/other notices already go out via `Sms::SendMessage`).

### 2. Payment Inquiry Single — `POST {baseURL}/api/PaymentInquiry`

Fetches status for one voucher. Request: `consumerNumber`, `AuthID`,
`transactionDate`.

**Open question, not yet answered by KuickPay**: `AuthID` is the bank's transaction
authorization code — we would not know this value until *after* the candidate has
already paid, so it's unclear how this endpoint is meant to be called for an
as-yet-unpaid or newly-paid voucher whose AuthID we don't have. Needs clarifying
with KuickPay before this endpoint can be relied on. Do not assume a blank/omitted
`AuthID` works — verify.

Response (success, `isSettled: true`): `VoucherNumber`, `amountTransaction`,
`authID`, `paymentReceivedThrough` (e.g. `"TMF"` — a bank/channel code, decode
during implementation), `settlement_Date_Time`.

### 3. Bill Payment Bulk Inquiry — `POST {baseURL}/api/BillPaymentBulkInquiry`

Fetches **every** settled transaction for a given date, in bulk. Request:
`institutionID`, `transactionDate` (`yyyyMMdd`).

No `AuthID` needed — this is likely the more practical polling mechanism for
"has this voucher been paid yet," by fetching the day's list and matching our own
`consumer_Number` against it, rather than depending on the single-inquiry endpoint's
unresolved `AuthID` requirement above.

Response array per transaction: `consumer_Number`, `registrationNumber`,
`transaction_Date_Time`, `settlement_Date_Time`, `amountTransaction`, `authID`,
`bank`, `isSettled`.

This is also the direct source for the client's existing manual CSV-download-from-
portal report — a scheduled job calling this daily and writing the results into our
own `Payment`/`PaymentEvent` model would replace that manual step entirely.

### Shared response codes (all 3 endpoints)

| Code | Meaning |
|---|---|
| `00` | Success |
| `01` | Blank parameter sent |
| `04` | Wrong credentials |
| `05` | Processing failed / service fail |

## How this maps onto the existing codebase (not yet built, for orientation only)

- Likely lands as a new `Payments::Providers::KuickpayHybridAdapter` (or similar),
  isolated the same way `KuickpayHostedCheckoutAdapter` already is — per
  `AGENTS.md`'s "application code must not directly depend on ... KuickPay ...
  APIs" rule. Two adapters for two KuickPay products (hosted checkout vs. hybrid
  voucher) under the same `Payments::Providers` namespace, not one adapter trying
  to do both.
- `Payment.provider_code` already distinguishes providers — candidate picks card
  (hosted checkout) or OTC/wallet (hybrid) at checkout, and the resulting
  `Payment` row's provider fields differ accordingly (`provider_session_id`/
  `checkout_url` for hosted checkout vs. a voucher/consumer number field for
  hybrid — may need a new column, or reuse `provider_order_id`, decide during
  implementation).
- Status polling (`Bill Payment Bulk Inquiry`) is a background job candidate —
  same shape as other scheduled/reconciliation jobs already in this codebase
  (e.g. `config/recurring.yml`'s existing entries).
- The 4 candidate-facing payment channels this unlocks (per the BPS guide, which
  also described the channels even though its own live-call model was rejected):
  banking app, bank OTC/counter/ATM, QR, KuickPay card portal — voucher/consumer
  number works the same way across all of them from the candidate's side.

## Open items before coding starts

1. **`AuthID` question** — send to KuickPay, per above.
2. **Which channels can pay a Hybrid-model voucher** — confirm all 4 (banking app,
   OTC/counter/ATM, QR, card portal) work against a voucher created via
   `insertPPMVoucher`, not just a subset.
3. **Production base URL** — only the UAT host is documented here.
4. **Auth credentials** — confirm whether Hybrid API credentials are separate from
   the existing hosted-checkout `KUICKPAY_COMPANY_ID`/`KUICKPAY_SECURED_KEY` pair.
5. **Where `registrationNumber` should map to** in our own schema (likely
   `payment.provider_order_id`, to be confirmed against how `Payment` uniqueness/
   idempotency already works for the hosted-checkout adapter).
6. **Duplicate/mismatch handling** — the BPS guide documented explicit response
   codes for duplicate/mismatched amounts; confirm whether the Hybrid model has
   equivalent protections, since `insertPPMVoucher` could plausibly be called
   twice for the same payment attempt.

## Client-facing framing (for later use — not yet sent)

The client asked how we'd manage OTC/wallet payments given their current
KuickPay-portal-based manual process. The following line is the intended framing
once we're ready to explain the new approach to them — saved here so it isn't
re-drafted from scratch later:

> This maps 1:1 onto your client's current manual process — just automated via API:

Intended pairing (once actually sent): show today's manual steps (create code on
portal → share with candidate → candidate pays via Easypaisa/JazzCash/bank →
manually download report) side-by-side with the automated equivalent (system
creates the voucher via `Insert Voucher` → candidate sees it in-app → candidate
pays the same way as today → system pulls settlement data automatically via
`Bill Payment Bulk Inquiry`) — reassuring them the underlying payment experience
for candidates and banks doesn't change, only the manual steps on staff's side
are removed.
