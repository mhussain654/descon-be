# frozen_string_literal: true

class PaymentReconciliationFinding < ApplicationRecord
  STATES = %w[open resolved].freeze

  belongs_to :payment_reconciliation_run
  belongs_to :payment, optional: true

  validates :finding_code, presence: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :state_code, inclusion: { in: STATES }
  validates :finding_code, uniqueness: { scope: %i[payment_reconciliation_run_id payment_id] }
end
