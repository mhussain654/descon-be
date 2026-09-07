# frozen_string_literal: true

# One of the 15 canonical, ordered stages a candidate assignment moves through from
# registration to mobilization abroad. System-defined stages are seeded and protected from
# being renamed, reordered, or deleted.
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

  # The initial workflow stage every new candidate assignment starts in.
  def self.registered
    find_by!(code: 'registered')
  end

  # The I18n key prefix under which this model's translated names are looked up.
  def self.i18n_name_scope
    'reference_data.workflow_stages'
  end

  private

  # Callback: blocks deletion of any stage that is marked as system-defined in the database.
  def prevent_system_destroy
    return unless system_defined_in_database

    errors.add(:base, :invalid)
    throw :abort
  end

  # Blocks changes to the code, position, or system_defined flag on a system-defined stage.
  def protect_system_definition_changes
    return unless system_defined_in_database

    restricted_fields = %w[code position system_defined]
    return unless changes_to_save.keys.intersect?(restricted_fields)

    errors.add(:base, :invalid)
  end
end
