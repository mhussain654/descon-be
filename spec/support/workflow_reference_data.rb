# frozen_string_literal: true

module WorkflowReferenceData
  def ensure_canonical_workflow_stages!
    WorkflowStage::CANONICAL_STAGES.each do |attributes|
      WorkflowStage.find_or_create_by!(code: attributes.fetch(:code)) do |stage|
        stage.position = attributes.fetch(:position)
        stage.system_defined = true
        stage.active = true
      end
    end
  end
end

RSpec.configure do |config|
  config.include WorkflowReferenceData
end
