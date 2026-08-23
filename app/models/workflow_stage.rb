# frozen_string_literal: true

class WorkflowStage < ApplicationRecord
  include HasLocalizedName

  CANONICAL_STAGES = [
    { code: 'registered', position: 1 },
    { code: 'documents_pending', position: 2 },
    { code: 'documents_uploaded', position: 3 },
    { code: 'under_verification', position: 4 },
    { code: 'verified', position: 5 },
    { code: 'fee_pending', position: 6 },
    { code: 'fee_paid', position: 7 },
    { code: 'documents_shared_with_qatar_bu', position: 8 },
    { code: 'qvc_appointment_booked', position: 9 },
    { code: 'qvc_completed_outcome_received', position: 10 },
    { code: 'visa_issued_or_rejected', position: 11 },
    { code: 'appeared_for_protection', position: 12 },
    { code: 'protected_ready_to_fly', position: 13 },
    { code: 'flight_details_uploaded', position: 14 },
    { code: 'mobilized', position: 15 }
  ].freeze

  has_many :candidate_assignments, foreign_key: :current_workflow_stage_id, inverse_of: :current_workflow_stage,
                                   dependent: :restrict_with_exception
  has_many :from_candidate_stage_histories, class_name: 'CandidateStageHistory', foreign_key: :from_workflow_stage_id,
                                            inverse_of: :from_workflow_stage, dependent: :restrict_with_exception
  has_many :to_candidate_stage_histories, class_name: 'CandidateStageHistory', foreign_key: :to_workflow_stage_id,
                                          inverse_of: :to_workflow_stage, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :position, presence: true, uniqueness: true, numericality: { only_integer: true, greater_than: 0 }
  validates :active, :system_defined, inclusion: { in: [true, false] }
  validate :protect_system_definition_changes, on: :update

  before_destroy :prevent_system_destroy

  def self.registered
    find_by!(code: 'registered')
  end

  def self.i18n_name_scope
    'reference_data.workflow_stages'
  end

  private

  def prevent_system_destroy
    return unless system_defined?

    errors.add(:base, :invalid)
    throw :abort
  end

  def protect_system_definition_changes
    return unless system_defined?

    restricted_fields = %w[code position]
    return unless changes_to_save.keys.intersect?(restricted_fields)

    errors.add(:base, :invalid)
  end
end
