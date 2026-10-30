# Known issue: card payments stay "Pending" after a successful payment

Status: open, fix deferred. Found 2026-10-30 while testing card payment on
production (KuickPay sandbox, company ID `01234`).

## Symptom

A candidate pays by card in the mobile app. KuickPay shows success and the
payment window closes, but the payment screen keeps showing **Pending** and the
candidate never moves to `fee_paid`.

## Cause

A card payment is marked paid only when our return endpoint runs:

1. After payment, KuickPay sends the payment window to
   `GET /api/v1/payments/hosted_checkout/kuickpay/return?orderid=...`.
2. `Api::V1::Payments::HostedCheckoutReturnsController` calls
   `Payments::VerifyPaymentStatusService`, which asks KuickPay's status API
   (`/checkout/api/status`) once.
3. Only a reply with `gatewayResponse.paymentStatus == "00"` marks the payment
   paid and moves the candidate to `fee_paid`.

In the mobile app,
`descon-fe/mobile/src/features/candidate/payments/components/HostedCheckoutWebView.tsx`
closes the WebView as soon as it sees the return URL start loading
(`handleShouldStartLoad` / `handleNavigationStateChange` call `onClose()`).
Closing the modal unmounts the WebView and cancels that request, so it never
reaches the server. Step 2 never runs, and nothing else ever re-checks.

Evidence from the test payment (`PAY-TEST-PAY-F6B473-BC44688A9436`): its only
`PaymentEvent` was `create_session/session_created`. There was no `return` log
line and no `status_check` event. Running the status check by hand afterwards
returned `paymentStatus "00"` and marked the payment paid, so KuickPay and
the server-side status check both work.

## Impact

- A real candidate who pays by card stays at Pending, and their fee is not
  recorded until someone re-checks it by hand.
- The same happens if the candidate closes the window, loses signal or the app
  is killed before the return URL loads. Even with the app fixed, nothing
  re-checks later.

## Workaround (until fixed)

Re-check a stuck payment from the production Rails console:

```ruby
payment = Payment.find_by!(provider_code: 'kuickpay', provider_order_id: 'PAY-...')
Payments::VerifyPaymentStatusService.call(payment:, request_id: "console-recheck")
payment.reload.status_code # => "paid" when KuickPay confirms it
```

Every check is saved as a `PaymentEvent` (`event_source: 'status_check'`) with
KuickPay's raw reply, so it is safe to run more than once.

## Planned fix

1. **Mobile:** when the WebView reaches the return URL, have the app request
   that URL itself and wait for it to finish, then close the window and
   refresh eligibility.
2. **Backend:** a recurring job (like `Payments::PollVoucherSettlementsJob`)
   that runs `VerifyPaymentStatusService` for every `checkout_pending` card
   payment that has not expired yet, every few minutes. This covers the cases
   the app cannot, such as a closed window or a killed app.

## Related, also deferred

- While a card checkout is open, the payment screen hides **Pay now** and
  shows "We haven't heard back from your payment provider yet". The server can
  reopen the same session, so a "Continue payment" button would let the
  candidate get back to it. Today they wait for the 30-minute expiry.
- The fee shows as `1500.0 PKR` instead of `1,500 PKR` on the payment screen.
- Production still uses KuickPay's sandbox hosts with the sandbox company ID
  `01234`. When the live details arrive, switch the company ID (`10420`), the
  base URL and the secured key together; `KUICKPAY_INSTITUTION_ID` stays
  `10420` for payment codes.
