# frozen_string_literal: true

module Candidates
  module Documents
    UploadedFileDetails = Data.define(:filename, :content_type, :byte_size, :checksum_sha256)
  end
end
