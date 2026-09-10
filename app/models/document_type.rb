# frozen_string_literal: true

# Reference data: a kind of document a candidate can upload (e.g. passport, CNIC front/back),
# describing whether it requires a document number/expiry date and whether it supports OCR.
class DocumentType < ApplicationRecord
  include HasLocalizedName

  # Passport/CNIC front/back/next-of-kin-CNIC are "auto-filled, editable
  # only by authorized HR users" per the requirements doc -- a hardcoded
  # code list (mirroring PoliceCharacterCompliance::PCC_REQUIREMENT_CODE's
  # identical pattern) rather than a new DB column, since this is a fixed
  # business rule with no admin-configurable UI, not runtime-editable
  # reference data. PCC also `requires_expiry` but must never trigger OCR,
  # so this is intentionally independent of that column.
  OCR_EXTRACTION_DOCUMENT_TYPE_CODES = %w[passport cnic_front cnic_back next_of_kin_cnic].freeze

  has_many :document_requirements, dependent: :restrict_with_exception
  has_many :candidate_documents, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name_en, :name_ur, presence: true
  validates :active, :requires_number, :requires_expiry, inclusion: { in: [true, false] }

  # True if this document type is one of the fixed set that OCR extraction runs against.
  def supports_ocr_extraction?
    OCR_EXTRACTION_DOCUMENT_TYPE_CODES.include?(code)
  end
end
