# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Exposes the document-review queue: candidate document submissions
      # waiting on (or already given) a staff verification/rejection
      # decision.
      class DocumentSubmissionsController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_review_not_allowed

        # Returns a paginated, filtered document-review queue with a
        # summary of counts by status.
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

        # Returns full detail for a single document submission, including
        # the candidate, assignment context and each document's review
        # state.
        def show
          authorize document_submission, policy_class: ::Admin::DocumentSubmissionPolicy

          render_success(data: ::Admin::DocumentSubmissionDetailSerializer.new(document_submission).as_json)
        end

        private

        # Scopes the document-submission table to what the current staff
        # member is authorized to view.
        def document_submission_scope
          policy_scope(CandidateDocumentSubmission, policy_scope_class: ::Admin::DocumentSubmissionPolicy::Scope)
        end

        # Loads the requested document submission with its assignment and
        # per-document review associations preloaded, raising if none
        # matches the given public id.
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

        # Renders a not-allowed error when Pundit denies this review action.
        def render_review_not_allowed
          render_api_error(ReviewNotAllowedError.new)
        end
      end
    end
  end
end
