# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class DocumentSubmissionsController < ProtectedController
        def create
          authorize current_candidate, policy_class: ::Candidates::DocumentSubmissionPolicy

          render_submission_response
        end

        private

        def render_submission_response
          render_idempotent_response(
            scope: 'candidate.document_submissions.create',
            subject: current_candidate,
            fingerprint: submission_fingerprint
          ) { success_payload(data: serialized_result, status: :created) }
        end

        def serialized_result
          result = ::Candidates::DocumentSubmissions::SubmitService.call(
            candidate: current_candidate,
            request_id: request.request_id
          )

          ::Candidates::DocumentSubmissionSerializer.new(result).as_json
        end

        def submission_fingerprint
          return if request.headers['Idempotency-Key'].blank?

          ::Candidates::DocumentSubmissions::SubmissionFingerprint.call(request:)
        end
      end
    end
  end
end
