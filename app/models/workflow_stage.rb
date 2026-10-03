# frozen_string_literal: true

# The catalog of stage *meanings* a candidate assignment can move through
# (code + localized name). Which stages a candidate actually passes, and in
# what order, comes from their assignment's MobilizationProcess -- `position`
# here is only the catalog's display order, never the workflow order.
# System-defined stages are seeded and protected from being renamed,
# reordered, or deleted.
class WorkflowStage < ApplicationRecord
  include HasLocalizedName

  CANONICAL_STAGES = [
    { code: 'registered', position: 1 },
    { code: 'documents_pending', position: 2 },
    { code: 'documents_uploaded', position: 3 },
    { code: 'under_verification', position: 4 },
    { code: 'verified', position: 5 },
    { code: 'campaign_nomination', position: 6 },
    { code: 'medical_pending', position: 7 },
    { code: 'medical_completed', position: 8 },
    { code: 'medical_appointment', position: 9 },
    { code: 'medical_fit', position: 10 },
    { code: 'gamca_medical_pending', position: 11 },
    { code: 'gamca_medical_completed', position: 12 },
    { code: 'e_number_processing', position: 13 },
    { code: 'e_number_requested', position: 14 },
    { code: 'e_number_received', position: 15 },
    { code: 'biometric_completed', position: 16 },
    { code: 'visa_stamping_case_prepared', position: 17 },
    { code: 'fee_pending', position: 18 },
    { code: 'fee_paid', position: 19 },
    { code: 'documents_shared_with_qatar_bu', position: 20 },
    { code: 'qvc_appointment_booked', position: 21 },
    { code: 'qvc_completed_outcome_received', position: 22 },
    { code: 'visa_processing', position: 23 },
    { code: 'visa_stamping_case_sent', position: 24 },
    { code: 'visa_issued_or_rejected', position: 25 },
    { code: 'protection_call', position: 26 },
    { code: 'appeared_for_protection', position: 27 },
    { code: 'ticket_handover', position: 28 },
    { code: 'flight_details_uploaded', position: 29 },
    { code: 'mobilized', position: 30 }
  ].freeze

  has_many :mobilization_process_stages, dependent: :restrict_with_exception
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

  before_destroy :prevent_system_destroy, prepend: true

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
