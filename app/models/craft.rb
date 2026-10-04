# frozen_string_literal: true

# Reference data: a trade/occupation (craft) a candidate is recruited for, used to scope
# candidate assignments and document requirements. `is_driver` (admin-managed) marks driver
# crafts, which receive driver-only document requirements such as the Qatar driving licence.
class Craft < ApplicationRecord
  include HasLocalizedName

  has_many :candidate_assignments, dependent: :restrict_with_exception
  has_many :document_requirements, dependent: :restrict_with_exception

  scope :active, -> { where(active: true) }

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name_en, :name_ur, presence: true
  validates :active, :is_driver, inclusion: { in: [true, false] }
end
