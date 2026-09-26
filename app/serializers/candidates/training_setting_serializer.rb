# frozen_string_literal: true

module Candidates
  # Candidate-facing shape -- just the link. No `updated_by` (an internal
  # staff actor isn't the candidate's business, same rationale as
  # CandidateWorkflows::VisaDecisionSerializer omitting it).
  class TrainingSettingSerializer
    def initialize(setting)
      @setting = setting
    end

    def as_json(*)
      { url: @setting.url }
    end
  end
end
