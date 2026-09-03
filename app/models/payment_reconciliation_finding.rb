# frozen_string_literal: true

class PaymentReconciliationFinding < ApplicationRecord
  STATES = %w[open resolved].freeze

  belongs_to :payment_reconciliation_run
  belongs_to :payment, optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :finding_code, presence: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :state_code, inclusion: { in: STATES }
  validates :finding_code, uniqueness: { scope: %i[payment_reconciliation_run_id payment_id] }
  validates :resolution_note, presence: true, if: :resolved?

  scope :open_state, -> { where(state_code: 'open') }

  def open? = state_code == 'open'
  def resolved? = state_code == 'resolved'

  def resolve!(by:, note:)
    update!(state_code: 'resolved', resolved_at: Time.current, resolved_by: by, resolution_note: note)
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end
