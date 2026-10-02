# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets any authenticated candidate read the shared support number for
      # the app's "Help & support" action -- no ownership scoping, mirroring
      # TrainingSettingsController.
      class SupportSettingsController < ProtectedController
        def show
          authorize current_candidate, policy_class: ::Candidates::SupportSettingPolicy

          setting = ::SupportSetting.current
          set_private_state_headers(updated_at: setting.updated_at, etag_key: 'support_setting')
          render_success(data: ::Candidates::SupportSettingSerializer.new(setting).as_json)
        end
      end
    end
  end
end
