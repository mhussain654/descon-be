# frozen_string_literal: true

# Global default; existing deployment values are retained until an admin changes it.
class OnboardingFeeSetting < ApplicationRecord
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :singleton_guard, inclusion: { in: [true] }
  validates :amount, numericality: { greater_than: 0, less_than: 100_000_000 }

  def self.current
    record = find_by(singleton_guard: true)
    return record if record

    create_or_find_by!(singleton_guard: true) do |setting|
      setting.amount = ENV.fetch('ONBOARDING_FEE_AMOUNT', '1500.00')
    end
  end
end
