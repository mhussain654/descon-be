# September meeting follow up

OTP validity defaults to 600 seconds (10 minutes), with the existing 60-second resend cooldown and five-attempt limit. Deployments that already set OTP_EXPIRY_SECONDS must update that setting to 600; changing the code default cannot override a deployed environment value.

Unknown/inactive CNIC responses use the agreed English and Urdu non-registration wording. Candidate lookup remains Candidate.active.find_by(cnic:): no assignment or mobilization-stage condition is introduced. Existing inactive-account restrictions remain intact. The message no longer echoes the submitted CNIC. SMS identifies the application as MPS Connect and uses the configured expiry duration.

The API shape and error code candidate_cnic_not_found remain unchanged. Desktop logo changes and payment finalization are deferred. Country-specific document/workflow completion still requires MPS-approved input for provisional countries.
