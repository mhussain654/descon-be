# frozen_string_literal: true

module CandidateImportReferenceData
  WORKFLOW_STAGE_RECORDS = [
    { code: 'registered', position: 1, system_defined: true },
    { code: 'documents_pending', position: 2, system_defined: true }
  ].freeze

  CATALOG_RECORDS = [
    { model_class: Country, code: 'qatar', name_en: 'Qatar', name_ur: 'قطر' },
    { model_class: Country, code: 'uae', name_en: 'United Arab Emirates', name_ur: 'متحدہ عرب امارات' },
    {
      model_class: Project,
      code: 'qatar_infrastructure',
      name_en: 'Qatar Infrastructure',
      name_ur: 'قطر انفراسٹرکچر'
    },
    { model_class: Project, code: 'qatar_energy', name_en: 'Qatar Energy', name_ur: 'قطر انرجی' },
    { model_class: Craft, code: 'electrician', name_en: 'Electrician', name_ur: 'الیکٹریشن' },
    { model_class: Craft, code: 'welder', name_en: 'Welder', name_ur: 'ویلڈر' }
  ].freeze

  def ensure_candidate_import_reference_data!
    WORKFLOW_STAGE_RECORDS.each { |attributes| ensure_workflow_stage!(**attributes) }
    CATALOG_RECORDS.each { |attributes| ensure_catalog_record!(**attributes) }
  end

  private

  def ensure_workflow_stage!(code:, position:, system_defined:)
    WorkflowStage.find_or_create_by!(code:) do |stage|
      stage.position = position
      stage.system_defined = system_defined
      stage.active = true
    end
  end

  def ensure_catalog_record!(model_class:, code:, name_en:, name_ur:)
    model_class.find_or_create_by!(code:) do |record|
      record.name_en = name_en
      record.name_ur = name_ur
      record.active = true
    end
  end
end

RSpec.configure do |config|
  config.include CandidateImportReferenceData
end
