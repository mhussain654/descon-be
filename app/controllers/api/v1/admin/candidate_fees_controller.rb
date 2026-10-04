# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateFeesController < ProtectedStaffController
        def show
          authorize ::OnboardingFeeSetting, :show?, policy_class: ::Admin::OnboardingFeePolicy
          authorize candidate, :show?, policy_class: ::Admin::CandidatePolicy
          render_success(data: serialized)
        end

        def update
          authorize ::OnboardingFeeSetting, :update?, policy_class: ::Admin::OnboardingFeePolicy
          authorize candidate, :show?, policy_class: ::Admin::CandidatePolicy
          raise NoCurrentAssignmentError unless assignment

          ::Admin::Payments::UpdateFeeService.call(
            actor: current_user, record: assignment, candidate:, request_id: request.request_id, **fee_params
          )
          render_success(data: serialized)
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidatePolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def assignment = candidate.current_assignment

        def fee_params
          payload = params.expect(fee: %i[amount expected_version reason])
          raise ValidationError.new(field: 'fee.amount') unless payload.key?(:amount)

          payload.to_h.symbolize_keys
        end

        def serialized
          ::Admin::OnboardingFeeSerializer.new(setting: ::OnboardingFeeSetting.current, assignment:).as_json
        end
      end
    end
  end
end
