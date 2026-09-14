# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets any authenticated candidate view the one shared training link --
      # not per-candidate content, so unlike other candidate resources there's
      # no ownership scoping, just an active-session check.
      class TrainingSettingsController < ProtectedController
        def show
          authorize current_candidate, policy_class: ::Candidates::TrainingSettingPolicy

          setting = ::TrainingSetting.current
          set_private_state_headers(updated_at: setting.updated_at, etag_key: 'training_setting')
          render_success(data: ::Candidates::TrainingSettingSerializer.new(setting).as_json)
        end
      end
    end
  end
end
