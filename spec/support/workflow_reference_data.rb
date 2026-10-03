# frozen_string_literal: true

# The workflow stage catalog plus the published mobilization processes (and
# the countries they're scoped to) -- seeded once per suite run, outside the
# per-example transaction, exactly as db/seeds.rb does. A factory country
# with a random code therefore resolves to the provisional common process;
# use `process_country(:qatar)` for a country process.
module WorkflowReferenceData
  PROCESS_COUNTRIES = [
    { code: 'qatar', name_en: 'Qatar', name_ur: 'قطر' },
    { code: 'saudi_arabia', name_en: 'Saudi Arabia', name_ur: 'سعودی عرب' }
  ].freeze

  module_function

  def ensure_canonical_workflow_stages!
    WorkflowStage::CANONICAL_STAGES.each do |attributes|
      WorkflowStage.find_or_create_by!(code: attributes.fetch(:code)) do |stage|
        stage.position = attributes.fetch(:position)
        stage.system_defined = true
        stage.active = true
      end
    end
  end

  def ensure_mobilization_processes!
    ensure_canonical_workflow_stages!
    PROCESS_COUNTRIES.each do |attributes|
      Country.find_or_create_by!(code: attributes.fetch(:code)) do |country|
        country.assign_attributes(name_en: attributes.fetch(:name_en), name_ur: attributes.fetch(:name_ur))
      end
    end
    MobilizationProcesses::Seeder.call
  end

  def process_country(code) = Country.find_by!(code: code.to_s)
end

RSpec.configure do |config|
  config.include WorkflowReferenceData
end
