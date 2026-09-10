# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view a candidate's current (non-superseded) bank detail submission,
      # masking the account number unless the viewer is authorized to see it unmasked.
      class CandidateBankDetailsController < ProtectedStaffController
        # Returns the candidate's active bank detail record, masked or unmasked depending on policy,
        # and audit-logs the view whenever the unmasked account number is revealed.
        def show
          authorize CandidateBankDetail, :show?, policy_class: ::Admin::CandidateBankDetailPolicy
          audit_unmasked_view! if reveal_account_number?

          render_success(data: ::Admin::CandidateBankDetailSerializer.new(
            candidate_bank_detail,
            reveal_account_number: reveal_account_number?
          ).as_json)
        end

        private

        # Loads the target candidate's current, non-superseded bank detail record, raising a
        # not-found error if the candidate has no assignment or no active bank detail.
        def candidate_bank_detail
          @candidate_bank_detail ||= begin
            assignment_id = target_candidate.current_assignment&.id
            raise CandidateBankDetailNotFoundError if assignment_id.blank?

            record = CandidateBankDetail.find_by(candidate_assignment_id: assignment_id, superseded_at: nil)
            raise CandidateBankDetailNotFoundError if record.blank?

            record
          end
        end

        # Finds the candidate named in the route, raising if not found.
        def target_candidate
          @target_candidate ||= ::Candidate.find_by!(public_id: params.expect(:candidate_id))
        end

        # Checks whether the current staff user's policy allows seeing the unmasked account number.
        def reveal_account_number?
          ::Admin::CandidateBankDetailPolicy.new(current_user, candidate_bank_detail).view_unmasked?
        end

        # Records an audit trail entry for this staff member viewing the unmasked bank details.
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
