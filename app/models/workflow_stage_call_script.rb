# frozen_string_literal: true

# The opening-announcement script for one canonical workflow stage's
# automatically-triggered AI voice call (see AiCalls::TriggerWorkflowStageCallService).
# The only DB-editable content in the AI voice calling feature -- the
# underlying call guardrails/tool-use rules stay repo-committed and are
# never exposed here. `workflow_stage_code` is restricted to
# WorkflowStage::CANONICAL_STAGES: admin can edit/enable/disable the script
# for a canonical stage, never add or remove one.
class WorkflowStageCallScript < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/
  LANGUAGES = %w[en ur].freeze

  belongs_to :updated_by, class_name: 'User', inverse_of: :updated_workflow_stage_call_scripts, optional: true

  before_validation :normalize_codes

  validates :workflow_stage_code, presence: true, uniqueness: true, format: { with: CODE_FORMAT },
                                  inclusion: { in: -> { WorkflowStage::CANONICAL_STAGES.map { |s| s.fetch(:code) } } }
  validates :announcement, presence: true
  validates :language_code, presence: true, inclusion: { in: LANGUAGES }
  validates :active, inclusion: { in: [true, false] }

  scope :active, -> { where(active: true) }

  private

  def normalize_codes
    self.workflow_stage_code = workflow_stage_code.to_s.strip.downcase.presence
    self.language_code = language_code.to_s.strip.downcase.presence || 'en'
    self.announcement = announcement.to_s.strip
  end
end
