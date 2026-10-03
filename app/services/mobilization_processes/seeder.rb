# frozen_string_literal: true

module MobilizationProcesses
  # Publishes every approved definition that doesn't exist yet, and verifies
  # the ones that do still match their complete definition -- country,
  # provisional flag and every stage's code, position, action type, required
  # flag and configuration. Idempotent (safe on every `db:seed`); never edits
  # a published version -- any difference raises so the change is made as a
  # new version instead.
  class Seeder < ApplicationService
    class MismatchError < StandardError
    end

    def initialize(definitions: Definitions::ALL)
      @definitions = definitions
    end

    def call
      @definitions.map { |definition| seed(definition) }
    end

    private

    def seed(definition)
      existing = MobilizationProcess.includes(:country, stages: :workflow_stage)
                                    .find_by(code: definition.fetch(:code), version: definition.fetch(:version))
      return verify!(existing, definition) if existing

      create_and_publish!(definition)
    end

    def create_and_publish!(definition)
      MobilizationProcess.transaction do
        process = MobilizationProcess.create!(
          code: definition.fetch(:code), version: definition.fetch(:version),
          country: country_for(definition), provisional: definition.fetch(:provisional)
        )
        definition.fetch(:stages).each.with_index(1) { |code, position| add_stage!(process, code, position) }
        process.publish!
        process
      end
    end

    def add_stage!(process, code, position)
      process.stages.create!(workflow_stage: WorkflowStage.find_by!(code:), **expected_stage_attributes(code, position))
    end

    def expected_stage_attributes(code, position)
      { position:, action_type: Definitions.action_type_for(code), required: true, configuration: {} }
    end

    def country_for(definition)
      code = definition.fetch(:country_code)
      code && Country.find_by!(code:)
    end

    def verify!(process, definition)
      return process if published_shape(process) == expected_shape(definition)

      raise MismatchError,
            "#{process.code} v#{process.version} is published with a different definition. " \
            'Publish the change as a new version instead of editing a published one.'
    end

    def published_shape(process)
      {
        country_code: process.country&.code, provisional: process.provisional,
        stages: process.stages.map do |stage|
          { code: stage.code, **stage.slice(:position, :action_type, :required, :configuration).symbolize_keys }
        end
      }
    end

    def expected_shape(definition)
      {
        country_code: definition.fetch(:country_code), provisional: definition.fetch(:provisional),
        stages: definition.fetch(:stages).each.with_index(1).map do |code, position|
          { code:, **expected_stage_attributes(code, position) }
        end
      }
    end
  end
end
