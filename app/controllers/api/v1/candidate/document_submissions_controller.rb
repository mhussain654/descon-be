# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets the logged-in candidate submit their uploaded identity/employment documents for review.
      class DocumentSubmissionsController < ProtectedController
        # Submits the candidate's current document batch for review, idempotently.
        def create
          authorize current_candidate, policy_class: ::Candidates::DocumentSubmissionPolicy

          render_submission_response
        end

        private

        # Wraps the submission in an idempotent response so a retried request doesn't resubmit.
        def render_submission_response
          render_idempotent_response(
            scope: 'candidate.document_submissions.create',
            subject: current_candidate,
            fingerprint: submission_fingerprint
          ) { success_payload(data: serialized_result, status: :created) }
        end

        # Runs the document submission service and serializes the resulting submission.
        def serialized_result
          result = ::Candidates::DocumentSubmissions::SubmitService.call(
            candidate: current_candidate,
            request_id: request.request_id
          )

          ::Candidates::DocumentSubmissionSerializer.new(result).as_json
        end

        # Computes an idempotency fingerprint from the request when an Idempotency-Key header is present.
        def submission_fingerprint
          return if request.headers['Idempotency-Key'].blank?

          ::Candidates::DocumentSubmissions::SubmissionFingerprint.call(request:)
        end
      end
    end
  end
end
