# frozen_string_literal: true

module CandidateWorkflows
  # Stores a staff-uploaded file (visa copy, flight ticket) in Active Storage
  # straight away and returns its blob, ready to attach -- the same way
  # candidate documents and bank proofs are stored.
  #
  # Attaching the raw upload instead leaves the actual upload to an
  # after-commit callback on the record, and that callback is lost whenever
  # the record is reloaded, or saved again through another instance, in the
  # same transaction (both happen in the workflow services). The database then
  # says the file is attached while nothing was ever written to S3.
  #
  # Use `.storing` around the transaction: it stores the file first and
  # deletes it again if the block fails, so no unattached file is left behind.
  class UploadedFileBlob < ApplicationService
    def initialize(uploaded_file:)
      @uploaded_file = uploaded_file
    end

    def call
      details = Candidates::Documents::UploadedFileInspector.call(uploaded_file: @uploaded_file)
      tempfile = @uploaded_file.tempfile
      tempfile.rewind
      ActiveStorage::Blob.create_and_upload!(io: tempfile, filename: details.filename,
                                             content_type: details.content_type, identify: false)
    ensure
      tempfile&.rewind
    end

    # Stores the file (when one was given), yields its blob, and discards the
    # blob if the block raises.
    def self.storing(uploaded_file)
      blob = call(uploaded_file:) if uploaded_file.present?
      yield blob
    rescue StandardError
      discard(blob)
      raise
    end

    # Deletes a blob made by `call` that ended up attached to nothing.
    def self.discard(blob)
      return if blob.blank? || blob.attachments.exists?

      blob.purge
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
