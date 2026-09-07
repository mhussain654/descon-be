# frozen_string_literal: true

# A single execution of the payment reconciliation process for a given date, tracking its
# status and owning the individual discrepancy findings it produces.
class PaymentReconciliationRun < ApplicationRecord
  STATES = %w[processing completed failed].freeze

  belongs_to :initiated_by, class_name: 'User', optional: true
  has_many :payment_reconciliation_findings, dependent: :restrict_with_exception

  validates :run_date, presence: true, uniqueness: true
  validates :status_code, inclusion: { in: STATES }
end
