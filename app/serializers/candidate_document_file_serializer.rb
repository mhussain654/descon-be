# frozen_string_literal: true

# One file of a multi-file candidate document (same shape for candidates and
# staff). Never includes a URL -- files are fetched through the short-lived
# document access endpoints.
class CandidateDocumentFileSerializer
  def initialize(file)
    @file = file
  end

  def as_json(*)
    {
      id: @file.public_id,
      side_code: @file.side_code,
      position: @file.position,
      file_name: @file.original_filename,
      content_type: @file.content_type,
      file_size: @file.byte_size
    }
  end
end
