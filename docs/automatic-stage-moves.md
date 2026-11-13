# Automatic stage moves

Staff should only act where they have something to enter or decide (client
request, Nov 2026). Every other move happens by itself
(`CandidateWorkflows::AutomaticTransitionService`, `FeeStageOpener`,
`Payments::PaymentStateApplier`).

| Event | Candidate moves to | Who acts |
|---|---|---|
| Candidate created or imported | Documents Pending | automatic |
| A required document uploaded | Documents Uploaded | automatic |
| Candidate taps "Submit for review" | Under Verification | candidate |
| Staff approve the last document and bank details | Verified, then Campaign Nomination | automatic |
| Medical result recorded as fit | Fee Pending | automatic |
| Fee paid (KuickPay) | Fee Paid, then the first step of the next phase | automatic |

After the fee, the next phase differs by country:

| Process | First step after Fee Paid | Shown in the app as |
|---|---|---|
| KSA | E-Number Processing | Tasheer Registration |
| Qatar | Documents Shared with Qatar BU | QVC Appointment |
| UAE, Oman, common | Visa Processing | Visa |

Each automatic step still goes through the stage's own prerequisites; a step
that isn't allowed stops the chain there. Automatic moves are recorded with a
reason code `auto_<event>` (e.g. `auto_documents_reviewed`, `auto_fee_paid`).

## Staff still record

Medical appointment (centre, date, time), medical result, e-number request and
receipt, biometric date, visa stamping case, QVC booking and outcome, visa
decision, protection call and appearance, ticket handover, flight details and
mobilization -- each needs a value or a decision only staff have.
