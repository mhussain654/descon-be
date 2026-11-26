# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class AssignmentAttributesBuilder
        NAMED_LOOKUPS = [Country, Project, Craft].freeze

        def initialize(actor:, campaign: nil)
          @actor = actor
          @campaign = campaign
        end

        def call(attributes:, row_errors:)
          {
            reference_number: validated_reference_number(attributes.fetch('reference_number'), row_errors:),
            current_workflow_stage: current_workflow_stage(attributes, row_errors:),
            country: country(attributes, row_errors:),
            project: project(attributes, row_errors:),
            craft: craft(attributes, row_errors:),
            campaign: @campaign,
            created_by: @actor
          }
        end

        private

        def current_workflow_stage(attributes, row_errors:)
          stage_code = RegisteredStage.normalize(attributes.fetch('workflow_stage_code'))
          referenced_record(WorkflowStage.where(active: true), stage_code, field: 'workflow_stage_code', row_errors:)
        end

        # Must be the campaign's country (the Test campaign takes any country).
        def country(attributes, row_errors:)
          record = referenced_record(Country.where(active: true), attributes.fetch('country_code'),
                                     field: 'country_code', row_errors:)
          if record && @campaign&.country && record != @campaign.country
            row_errors << { field: 'country_code', code: 'country_not_in_campaign' }
          end
          record
        end

        def project(attributes, row_errors:)
          referenced_record(
            Project.where(active: true),
            attributes.fetch('project_code'),
            field: 'project_code',
            row_errors:
          )
        end

        def craft(attributes, row_errors:)
          referenced_record(Craft.where(active: true), attributes.fetch('craft_code'), field: 'craft_code', row_errors:)
        end

        def validated_reference_number(raw_value, row_errors:)
          value = raw_value.to_s.strip.upcase
          return value if value.present?

          row_errors << { field: 'reference_number', code: 'missing_value' }
          nil
        end

        # Countries, projects and crafts match by code or -- since client files
        # carry names -- by English name, ignoring case and extra spaces (e.g.
        # "Qatar Infrastructure", "HSE Assistant"). Workflow stages match by code.
        def referenced_record(scope, raw_code, field:, row_errors:)
          value = raw_code.to_s.squish.downcase
          record = scope.find_by(code: value)
          record ||= scope.find_by('LOWER(name_en) = ?', value) if value.present? && NAMED_LOOKUPS.include?(scope.klass)
          return record if record.present?

          row_errors << { field:, code: "unknown_#{field}" }
          nil
        end
      end
    end
  end
end
