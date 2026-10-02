# frozen_string_literal: true

module MobilizationProcesses
  # Publishes every approved definition that doesn't exist yet, and verifies
  # the ones that do still match their definition exactly. Idempotent (safe on
  # every `db:seed`); never edits a published version -- a mismatch raises so
  # the change is made as a new version instead.
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
      existing = MobilizationProcess.includes(stages: :workflow_stage)
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
      process.stages.create!(
        workflow_stage: WorkflowStage.find_by!(code:),
        position:,
        action_type: Definitions.action_type_for(code)
      )
    end

    def country_for(definition)
      code = definition.fetch(:country_code)
      code && Country.find_by!(code:)
    end

    def verify!(process, definition)
      seeded_codes = process.stages.map(&:code)
      return process if seeded_codes == definition.fetch(:stages)

      raise MismatchError,
            "#{process.code} v#{process.version} is published with a different stage list than its definition. " \
            'Publish the change as a new version instead of editing a published one.'
    end
  end
end
