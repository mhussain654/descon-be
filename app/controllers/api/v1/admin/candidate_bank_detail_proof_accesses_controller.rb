# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateBankDetailProofAccessesController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_bank_detail_proof_access_forbidden

        def create
          authorize CandidateBankDetail, :access_proof?, policy_class: ::Admin::CandidateBankDetailPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::Admin::CandidateBankDetailAccessSerializer.new(access_result).as_json)
        end

        private

        def access_result
          @access_result ||= ::Admin::CandidateBankDetails::ProofAccessService.call(
            actor: current_user,
            bank_detail: candidate_bank_detail,
            request_id: request.request_id
          )
        end

        def candidate_bank_detail
          @candidate_bank_detail ||= begin
            assignment_id = target_candidate.current_assignment&.id
            raise CandidateBankDetailNotFoundError if assignment_id.blank?

            record = CandidateBankDetail.find_by(candidate_assignment_id: assignment_id, superseded_at: nil)
            raise CandidateBankDetailNotFoundError if record.blank?

            record
          end
        end

        def target_candidate
          @target_candidate ||= ::Candidate.find_by!(public_id: params.expect(:candidate_id))
        end

        def render_bank_detail_proof_access_forbidden
          render_api_error(BankDetailProofAccessForbiddenError.new)
        end
      end
    end
  end
end
