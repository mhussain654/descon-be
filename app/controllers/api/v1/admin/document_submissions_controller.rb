# frozen_string_literal: true

module Api
  module V1
    module Admin
      class DocumentSubmissionsController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_review_not_allowed

        def index
          authorize CandidateDocumentSubmission, policy_class: ::Admin::DocumentSubmissionPolicy

          query = ::Admin::DocumentReviewQueueQuery.new(scope: document_submission_scope, params:)
          submissions = query.call

          render_collection(
            data: submissions.map { |submission| ::Admin::DocumentReviewQueueItemSerializer.new(submission).as_json },
            pagination: query.pagination,
            meta: { summary: query.summary }
          )
        end

        def show
          authorize document_submission, policy_class: ::Admin::DocumentSubmissionPolicy

          render_success(data: ::Admin::DocumentSubmissionDetailSerializer.new(document_submission).as_json)
        end

        private

        def document_submission_scope
          policy_scope(CandidateDocumentSubmission, policy_scope_class: ::Admin::DocumentSubmissionPolicy::Scope)
        end

        def document_submission
          @document_submission ||= begin
            submission = CandidateDocumentSubmission
                         .preload(
                           candidate_assignment: %i[candidate country craft project],
                           submission_items: { candidate_document: %i[document_type verified_by] }
                         )
                         .find_by(public_id: params.expect(:id))
            raise DocumentSubmissionNotFoundError if submission.blank?

            submission
          end
        end

        def render_review_not_allowed
          render_api_error(ReviewNotAllowedError.new)
        end
      end
    end
  end
end
