# frozen_string_literal: true

module Api
  module V1
    module Admin
      class OnboardingFeeSettingsController < ProtectedStaffController
        def show
          authorize ::OnboardingFeeSetting, policy_class: ::Admin::OnboardingFeePolicy
          render_success(data: serialized(setting))
        end

        def update
          authorize ::OnboardingFeeSetting, policy_class: ::Admin::OnboardingFeePolicy
          record = ::Admin::Payments::UpdateFeeService.call(
            actor: current_user, record: setting, request_id: request.request_id, **fee_params
          )
          render_success(data: serialized(record))
        end

        private

        def setting = ::OnboardingFeeSetting.current

        def fee_params
          params.expect(fee: %i[amount expected_version reason]).to_h.symbolize_keys
        end

        def serialized(record)
          ::Admin::OnboardingFeeSerializer.new(setting: record).as_json
        end
      end
    end
  end
end
