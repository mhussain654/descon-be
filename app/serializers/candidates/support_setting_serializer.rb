# frozen_string_literal: true

module Candidates
  # Candidate-facing shape -- just the number (null until staff set one). No
  # `updated_by`, same rationale as TrainingSettingSerializer.
  class SupportSettingSerializer
    def initialize(setting)
      @setting = setting
    end

    def as_json(*)
      { phone_number: @setting.phone_number }
    end
  end
end
