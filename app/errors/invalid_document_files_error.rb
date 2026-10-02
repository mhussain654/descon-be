# frozen_string_literal: true

# A document upload whose file set doesn't satisfy its requirement's rules
# (count, side labels, front/back or page pairs, combined-PDF use). `reason`
# is a stable code clients can map; `details` carries the numbers involved.
class InvalidDocumentFilesError < BaseError
  REASONS = %w[
    too_few_files too_many_files side_code_required side_code_not_allowed duplicate_side_code
    incomplete_side_pair combined_must_be_alone combined_requires_pdf
  ].freeze

  def initialize(reason:, field: 'candidate_document.files', details: {})
    super(
      code: 'invalid_document_files',
      message: I18n.t("api.errors.invalid_document_files.#{reason}"),
      status: :unprocessable_content,
      field:,
      details: details.merge(reason:)
    )
  end
end
