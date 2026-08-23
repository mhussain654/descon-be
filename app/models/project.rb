# frozen_string_literal: true

class Project < ApplicationRecord
  include HasLocalizedName

  has_many :candidate_assignments, dependent: :restrict_with_exception
  has_many :document_requirements, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name_en, :name_ur, presence: true
  validates :active, inclusion: { in: [true, false] }
end
