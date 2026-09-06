# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Issues a short-lived signed URL so staff can view a candidate's
      # bank-account proof document, and records the access for audit
      # purposes.
      class CandidateBankDetailProofAccessesController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_bank_detail_proof_access_forbidden

        # Grants (and returns) time-limited access to the candidate's
        # current bank-detail proof file; never cached by the browser.
        def create
          authorize CandidateBankDetail, :access_proof?, policy_class: ::Admin::CandidateBankDetailPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::Admin::CandidateBankDetailAccessSerializer.new(access_result).as_json)
        end

        private

        # Requests and memoizes the signed access result from the proof-
        # access service, which also logs the access for audit purposes.
        def access_result
          @access_result ||= ::Admin::CandidateBankDetails::ProofAccessService.call(
            actor: current_user,
            bank_detail: candidate_bank_detail,
            request_id: request.request_id
          )
        end

        # Loads the candidate's current (non-superseded) bank detail
        # record, raising if the candidate has no active assignment or bank
        # detail on file.
        def candidate_bank_detail
          @candidate_bank_detail ||= begin
            assignment_id = target_candidate.current_assignment&.id
            raise CandidateBankDetailNotFoundError if assignment_id.blank?

            record = CandidateBankDetail.find_by(candidate_assignment_id: assignment_id, superseded_at: nil)
            raise CandidateBankDetailNotFoundError if record.blank?

            record
          end
        end

        # Loads the candidate named in the route, raising if no candidate
        # matches the given public id.
        def target_candidate
          @target_candidate ||= ::Candidate.find_by!(public_id: params.expect(:candidate_id))
        end

        # Renders a forbidden-access error when Pundit denies this action.
        def render_bank_detail_proof_access_forbidden
          render_api_error(BankDetailProofAccessForbiddenError.new)
        end
      end
    end
  end
end
