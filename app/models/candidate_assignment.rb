# frozen_string_literal: true

class CandidateAssignment < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :candidate
  belongs_to :country
  belongs_to :project
  belongs_to :craft
  belongs_to :current_workflow_stage, class_name: 'WorkflowStage'
  belongs_to :created_by, class_name: 'User'

  has_many :candidate_stage_histories, dependent: :restrict_with_exception
  has_many :candidate_bank_details, dependent: :restrict_with_exception
  has_many :candidate_documents, dependent: :restrict_with_exception
  has_many :candidate_document_submissions, dependent: :restrict_with_exception
  has_many :candidate_qvc_attempts, dependent: :restrict_with_exception
  has_one :candidate_protection_record, dependent: :restrict_with_exception
  has_many :payments, dependent: :restrict_with_exception
  has_many :communications, dependent: :restrict_with_exception
  has_many :candidate_workflow_events, dependent: :restrict_with_exception
  has_many :audit_events, dependent: :restrict_with_exception

  before_validation :assign_public_id, on: :create
  before_validation :normalize_reference_number
  before_validation :normalize_qvc_outcome_code

  validates :public_id, presence: true, uniqueness: true
  validates :reference_number, presence: true, uniqueness: true
  validates :qvc_outcome_code, format: { with: CODE_FORMAT }, allow_blank: true
  validate :qvc_outcome_fields_are_paired

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_reference_number
    self.reference_number = reference_number.to_s.strip.upcase
  end

  def normalize_qvc_outcome_code
    normalized = qvc_outcome_code.to_s.strip.downcase.presence
    self.qvc_outcome_code = 're_medical' if normalized == 're_medical_required'
    self.qvc_outcome_code ||= normalized
  end

  def qvc_outcome_fields_are_paired
    return if qvc_outcome_code.blank? && qvc_outcome_date.blank?
    return if qvc_outcome_fields_paired?

    errors.add(:qvc_outcome_code, :blank) if qvc_outcome_code.blank?
    errors.add(:qvc_outcome_date, :blank) if qvc_outcome_date.blank?
  end

  def qvc_outcome_fields_paired?
    qvc_outcome_code.present? == qvc_outcome_date.present?
  end
end
