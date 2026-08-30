# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateBankDetailsController < ProtectedStaffController
        def show
          authorize CandidateBankDetail, :show?, policy_class: ::Admin::CandidateBankDetailPolicy
          audit_unmasked_view! if reveal_account_number?

          render_success(data: ::Admin::CandidateBankDetailSerializer.new(
            candidate_bank_detail,
            reveal_account_number: reveal_account_number?
          ).as_json)
        end

        private

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

        def reveal_account_number?
          ::Admin::CandidateBankDetailPolicy.new(current_user, candidate_bank_detail).view_unmasked?
        end

        def audit_unmasked_view!
          ::Admin::CandidateBankDetails::UnmaskedViewAuditService.call(
            actor: current_user,
            bank_detail: candidate_bank_detail,
            request_id: request.request_id
          )
        end
      end
    end
  end
end
