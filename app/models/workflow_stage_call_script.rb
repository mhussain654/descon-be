# frozen_string_literal: true

# The content of one canonical workflow stage's automatically-triggered
# voice call (see AiCalls::TriggerWorkflowStageCallService): a RoboCall
# `voice_id` -- a fixed pre-recorded voice, the only thing sent for the call --
# and/or, for the ElevenLabs provider, an opening announcement.
# The only DB-editable content in the AI voice calling feature -- the
# underlying call guardrails/tool-use rules stay repo-committed and are
# never exposed here. `workflow_stage_code` is restricted to
# WorkflowStage::CANONICAL_STAGES: admin can edit/enable/disable the script
# for a canonical stage, never add or remove one.
#
# Stores both an English and an Urdu announcement (mirroring
# AiCalls::Prompts::ScenarioPrompt's existing opening_line pattern) rather
# than a single language_code tag -- the actual call always speaks in the
# *candidate's own* preferred_locale (see WorkflowStageAnnouncementPrompt),
# so a script needs both languages ready, not just one. `announcement_ur`
# may be blank while a stage's Urdu wording isn't ready yet;
# WorkflowStageAnnouncementPrompt falls back to `announcement_en` in that
# case rather than placing a call with no text.
class WorkflowStageCallScript < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/
  VOICE_ID_FORMAT = /\A[A-Za-z0-9_-]{1,32}\z/

  belongs_to :updated_by, class_name: 'User', inverse_of: :updated_workflow_stage_call_scripts, optional: true

  before_validation :normalize_codes

  validates :workflow_stage_code, presence: true, uniqueness: true, format: { with: CODE_FORMAT },
                                  inclusion: { in: -> { WorkflowStage::CANONICAL_STAGES.map { |s| s.fetch(:code) } } }
  # An active call needs something to play or say: a RoboCall voice, or (ElevenLabs) an announcement.
  validates :announcement_en, presence: true, if: -> { active && voice_id.blank? }
  validates :voice_id, format: { with: VOICE_ID_FORMAT }, allow_nil: true
  validates :active, inclusion: { in: [true, false] }

  scope :active, -> { where(active: true) }

  private

  def normalize_codes
    self.workflow_stage_code = workflow_stage_code.to_s.strip.downcase.presence
    %i[announcement_en announcement_ur voice_id].each do |attribute|
      self[attribute] = self[attribute].to_s.strip.presence
    end
  end
end
