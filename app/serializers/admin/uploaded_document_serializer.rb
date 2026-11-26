# frozen_string_literal: true

module Admin
  # One of a candidate's current documents, submitted or not, with its files.
  class UploadedDocumentSerializer
    def initialize(document)
      @document = document
    end

    def as_json(*)
      {
        id: @document.public_id,
        document_type: { code: @document.document_type.code, name: @document.document_type.name_for },
        status: @document.status_code,
        submitted: @document.submission_item.present?,
        uploaded_at: @document.uploaded_at&.utc&.iso8601,
        files: @document.files.map { |file| serialized_file(file) }
      }
    end

    private

    def serialized_file(file)
      { id: file.public_id, side_code: file.side_code, original_filename: file.original_filename,
        content_type: file.content_type, byte_size: file.byte_size }
    end
  end
end
