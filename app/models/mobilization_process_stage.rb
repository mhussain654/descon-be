# frozen_string_literal: true

# One ordered step of a MobilizationProcess: which catalog stage (meaning +
# localized name) sits at which position, and which kind of action moves a
# candidate into it (`action_type`), so clients pick the right form without
# ever branching on a country. Read-only once its process is published.
class MobilizationProcessStage < ApplicationRecord
  ACTION_TYPES = %w[
    none
    document_submission
    nomination
    medical_appointment
    medical_outcome
    payment
    e_number_processing
    e_number_request
    e_number_received
    biometric_completion
    visa_case_preparation
    visa_case_submission
    qvc_appointment
    qvc_outcome
    visa_processing
    visa_decision
    protection_call
    protection_appearance
    ticket_handover
    flight_details
    mobilization
  ].freeze

  belongs_to :mobilization_process, inverse_of: :stages
  belongs_to :workflow_stage

  # Each process's last stage -- reaching it means the candidate completed
  # their mobilization (Mobilized for Qatar, Ticket Handover for KSA...).
  scope :terminal, lambda {
    where(<<~SQL.squish)
      mobilization_process_stages.position = (
        SELECT MAX(sibling_stages.position) FROM mobilization_process_stages sibling_stages
        WHERE sibling_stages.mobilization_process_id = mobilization_process_stages.mobilization_process_id
      )
    SQL
  }

  validates :position, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :mobilization_process_id }
  validates :workflow_stage_id, uniqueness: { scope: :mobilization_process_id }
  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :required, inclusion: { in: [true, false] }
  validate :configuration_is_an_object
  validate :process_is_still_a_draft, on: :create

  before_destroy :prevent_published_destroy, prepend: true

  delegate :code, to: :workflow_stage

  # A published process's stages are frozen -- a change needs a new version.
  def readonly?
    (persisted? && mobilization_process&.published?) || super
  end

  private

  def configuration_is_an_object
    errors.add(:configuration, :invalid) unless configuration.is_a?(Hash)
  end

  def process_is_still_a_draft
    errors.add(:mobilization_process, :published_process_immutable) if mobilization_process&.published?
  end

  def prevent_published_destroy
    return unless mobilization_process&.published?

    errors.add(:base, :published_process_immutable)
    throw :abort
  end
end
