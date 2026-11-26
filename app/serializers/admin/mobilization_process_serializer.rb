# frozen_string_literal: true

module Admin
  # A mobilization process with its ordered stages, for the read-only view.
  class MobilizationProcessSerializer
    def initialize(process)
      @process = process
    end

    def as_json(*)
      {
        code: @process.code,
        version: @process.version,
        status: @process.status,
        country: DocumentRequirementSerializer.ref(@process.country),
        published_at: @process.published_at&.utc&.iso8601,
        stages: @process.stages.map { |stage| serialized_stage(stage) }
      }
    end

    private

    def serialized_stage(stage)
      { position: stage.position, code: stage.workflow_stage.code, name: stage.workflow_stage.name_for,
        required: stage.required }
    end
  end
end
