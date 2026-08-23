# frozen_string_literal: true

class DocumentType < ApplicationRecord
  include HasLocalizedName

  has_many :document_requirements, dependent: :restrict_with_exception
  has_many :candidate_documents, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name_en, :name_ur, presence: true
  validates :active, :requires_number, :requires_expiry, inclusion: { in: [true, false] }
end
