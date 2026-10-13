# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class AssignmentAttributesBuilder
        def initialize(actor:)
          @actor = actor
        end

        def call(attributes:, row_errors:)
          {
            reference_number: validated_reference_number(attributes.fetch('reference_number'), row_errors:),
            current_workflow_stage: current_workflow_stage(attributes, row_errors:),
            country: country(attributes, row_errors:),
            project: project(attributes, row_errors:),
            craft: craft(attributes, row_errors:),
            created_by: @actor
          }
        end

        private

        def current_workflow_stage(attributes, row_errors:)
          stage_code = RegisteredStage.normalize(attributes.fetch('workflow_stage_code'))
          referenced_record(WorkflowStage.where(active: true), stage_code, field: 'workflow_stage_code', row_errors:)
        end

        def country(attributes, row_errors:)
          referenced_record(
            Country.where(active: true),
            attributes.fetch('country_code'),
            field: 'country_code',
            row_errors:
          )
        end

        def project(attributes, row_errors:)
          referenced_record(
            Project.where(active: true),
            attributes.fetch('project_code'),
            field: 'project_code',
            row_errors:
          )
        end

        # Matched by code, or -- since client files carry job titles -- by the
        # craft's English name, ignoring case and extra spaces (e.g. "HSE Assistant").
        def craft(attributes, row_errors:)
          crafts = Craft.where(active: true)
          value = attributes.fetch('craft_code').to_s.squish.downcase
          record = crafts.find_by(code: value) || (value.present? && crafts.find_by('LOWER(name_en) = ?', value))
          return record if record

          row_errors << { field: 'craft_code', code: 'unknown_craft_code' }
          nil
        end

        def validated_reference_number(raw_value, row_errors:)
          value = raw_value.to_s.strip.upcase
          return value if value.present?

          row_errors << { field: 'reference_number', code: 'missing_value' }
          nil
        end

        def referenced_record(scope, raw_code, field:, row_errors:)
          code = raw_code.to_s.strip.downcase
          record = scope.find_by(code:)
          return record if record.present?

          row_errors << { field:, code: "unknown_#{field}" }
          nil
        end
      end
    end
  end
end
