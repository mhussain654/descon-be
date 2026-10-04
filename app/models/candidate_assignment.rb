# frozen_string_literal: true

# A candidate's placement against a specific country/project/craft, tracking its progress
# through its MobilizationProcess's stages, related documents, payments and communications.
#
# The process is resolved once, from the country, when the assignment is
# created and never re-resolved -- an in-flight candidate stays on the
# version they started with even after a newer one is published.
# `current_workflow_stage` (the stage meaning) and
# `current_mobilization_process_stage` (its place in this process) are kept
# in step here, so every writer of the current stage stays consistent.
class CandidateAssignment < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :candidate
  belongs_to :country
  belongs_to :project
  belongs_to :craft
  belongs_to :current_workflow_stage, class_name: 'WorkflowStage'
  belongs_to :mobilization_process
  belongs_to :current_mobilization_process_stage, class_name: 'MobilizationProcessStage'
  belongs_to :created_by, class_name: 'User'

  has_many :candidate_stage_histories, dependent: :restrict_with_exception
  has_many :candidate_bank_details, dependent: :restrict_with_exception
  has_many :candidate_documents, dependent: :restrict_with_exception
  has_many :candidate_document_submissions, dependent: :restrict_with_exception
  has_many :candidate_qvc_attempts, dependent: :restrict_with_exception
  has_one :candidate_protection_record, dependent: :restrict_with_exception
  has_many :candidate_visa_decisions, dependent: :restrict_with_exception
  has_many :candidate_medical_results, dependent: :restrict_with_exception
  has_one :candidate_flight_detail, dependent: :restrict_with_exception
  has_many :payments, dependent: :restrict_with_exception
  has_many :payment_events, through: :payments
  has_many :communications, dependent: :restrict_with_exception
  has_many :candidate_ai_calls, dependent: :restrict_with_exception
  has_many :candidate_workflow_events, dependent: :restrict_with_exception
  has_many :audit_events, dependent: :restrict_with_exception

  before_validation :assign_public_id, on: :create
  before_validation :resolve_mobilization_process, on: :create
  before_validation :sync_current_mobilization_process_stage
  before_validation :normalize_reference_number
  before_validation :normalize_qvc_outcome_code

  validates :onboarding_fee_amount, numericality: { greater_than: 0, less_than: 100_000_000 }, allow_nil: true
  validates :public_id, presence: true, uniqueness: true
  validates :reference_number, presence: true, uniqueness: true
  validates :qvc_outcome_code, format: { with: CODE_FORMAT }, allow_blank: true
  validate :qvc_outcome_fields_are_paired
  validate :current_stage_belongs_to_process

  # The next stage in this assignment's own process, or nil at its terminal stage.
  def next_process_stage
    mobilization_process&.next_stage_after(current_mobilization_process_stage)
  end

  # Whether this assignment is at or past the stage `code` in its own process
  # (false if its process doesn't include that stage).
  def reached_stage?(code)
    target = mobilization_process&.stage_with_code(code)
    target.present? && current_mobilization_process_stage.present? &&
      current_mobilization_process_stage.position >= target.position
  end

  def terminal_stage?
    current_mobilization_process_stage.present? &&
      current_mobilization_process_stage == mobilization_process&.terminal_stage
  end

  private

  # Attaches the destination country's active process (falling back to the
  # common provisional one) -- once, at creation.
  def resolve_mobilization_process
    self.mobilization_process ||= MobilizationProcess.resolve_for(country)
  end

  # Points the process-stage reference at the current stage's place in this
  # assignment's process whenever the current stage changes.
  def sync_current_mobilization_process_stage
    return if mobilization_process.blank? || current_workflow_stage.blank?
    return if process_stage_in_step?

    self.current_mobilization_process_stage = mobilization_process.stage_for(current_workflow_stage)
  end

  def process_stage_in_step?
    process_stage = current_mobilization_process_stage
    process_stage&.mobilization_process_id == mobilization_process_id &&
      process_stage.workflow_stage_id == current_workflow_stage_id
  end

  # A candidate can only ever stand on a stage that exists in their own process.
  def current_stage_belongs_to_process
    return if mobilization_process.blank? || current_workflow_stage.blank?
    return if mobilization_process.stage_for(current_workflow_stage).present?

    errors.add(:current_workflow_stage, :not_in_mobilization_process)
  end

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Trims and uppercases the assignment's reference number.
  def normalize_reference_number
    self.reference_number = reference_number.to_s.strip.upcase
  end

  # Trims and lowercases the QVC outcome code, mapping the legacy 're_medical_required' value
  # to the current 're_medical' code.
  def normalize_qvc_outcome_code
    normalized = qvc_outcome_code.to_s.strip.downcase.presence
    self.qvc_outcome_code = 're_medical' if normalized == 're_medical_required'
    self.qvc_outcome_code ||= normalized
  end

  # The QVC outcome code and outcome date must be set together or not at all.
  def qvc_outcome_fields_are_paired
    return if qvc_outcome_code.blank? && qvc_outcome_date.blank?
    return if qvc_outcome_fields_paired?

    errors.add(:qvc_outcome_code, :blank) if qvc_outcome_code.blank?
    errors.add(:qvc_outcome_date, :blank) if qvc_outcome_date.blank?
  end

  # Whether the QVC outcome code and outcome date are either both present or both blank.
  def qvc_outcome_fields_paired?
    qvc_outcome_code.present? == qvc_outcome_date.present?
  end
end
