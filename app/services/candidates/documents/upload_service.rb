# frozen_string_literal: true

module Candidates
  module Documents
    # Uploads one logical document -- one or more files, e.g. passport page 1
    # and page 2 -- against a requirement on the candidate's own checklist.
    # Every file is inspected by its actual content (never the browser-declared
    # type), the whole set is checked against the requirement's rules
    # (FileSetValidator) and scanned before any blob is stored, and the files
    # are then saved together as a new document version.
    #
    # `uploaded_files` is a list of `{ file:, side_code: }`.
    # rubocop:disable Metrics/ClassLength
    class UploadService < ApplicationService
      # `document_attributes` are the PCC dates (`issued_on`, `expires_on[_supplied]`) and the
      # next of kin's `next_of_kin_relation`, each used only by its own requirement.
      def initialize(candidate:, uploaded_files:, requirement_code:, request_id:, document_attributes: {})
        @candidate = candidate
        @next_of_kin_relation = document_attributes[:next_of_kin_relation].to_s.strip.downcase.presence
        @uploaded_files = Array(uploaded_files)
        @requirement_code = requirement_code.to_s.strip.downcase
        @request_id = request_id
        @issued_on = document_attributes[:issued_on]
        @expires_on_supplied = expires_on_supplied?(document_attributes)
      end

      def call
        blobs = []
        entries = validated_entries
        blobs = entries.map { |entry| build_blob(entry) }
        uploaded_document = persist_upload_and_advance_workflow(entries:, blobs:)
        enqueue_extraction(uploaded_document)
        ChecklistItemBuilder.call(requirement:, document: uploaded_document)
      rescue StandardError
        blobs.each { |blob| purge_blob(blob) }
        raise
      end

      private

      # Every check that needs no storage: request shape, then each file's
      # content and the set's rules, then scanning.
      def validated_entries
        validate_upload_request!
        entries = inspected_entries
        FileSetValidator.call(requirement:, entries:)
        scan!(entries)
        entries
      end

      def validate_upload_request!
        raise MissingFileError.new(field: 'candidate_document.files') if @uploaded_files.empty?
        raise InvalidRequirementError if requirement.blank?
        raise PccExpiryNotEditableError if pcc_requirement? && @expires_on_supplied

        validate_file_presence!
        pcc_issued_on
        validate_next_of_kin_relation!
      end

      # The next of kin's CNIC must say how they are related to the candidate.
      def validate_next_of_kin_relation!
        return unless next_of_kin_requirement?
        return if CandidateDocument::NEXT_OF_KIN_RELATIONS.include?(@next_of_kin_relation)

        raise ValidationError.new(field: 'candidate_document.next_of_kin_relation',
                                  message: I18n.t('api.errors.next_of_kin_relation_required'))
      end

      def next_of_kin_requirement?
        requirement.document_type.code == CandidateDocument::NEXT_OF_KIN_REQUIREMENT_CODE
      end

      # The cheap checks first, before reading any file's contents.
      def validate_file_presence!
        @uploaded_files.each_with_index do |entry, index|
          validate_file_size!(entry[:file], "candidate_document.files[#{index}].file")
        end
      end

      def validate_file_size!(file, field)
        raise MissingFileError.new(field:) if file.blank? || !file.respond_to?(:tempfile)
        raise EmptyFileError.new(field:) if file.size.to_i.zero?
        raise FileTooLargeError.new(field:) if file.size.to_i > requirement.maximum_file_size
      end

      def requirement
        @requirement ||= RequirementResolver.call(candidate: @candidate).find do |resolved_requirement|
          resolved_requirement.document_type.code == @requirement_code
        end
      end

      def inspected_entries
        default_side_code = requirement.default_side_code(file_count: @uploaded_files.size)
        @uploaded_files.map do |entry|
          {
            file: entry[:file],
            side_code: entry[:side_code].to_s.strip.downcase.presence || default_side_code,
            details: UploadedFileInspector.call(uploaded_file: entry[:file])
          }
        end
      end

      def scan!(entries)
        entries.each_with_index do |entry, index|
          MalwareScanner.call(uploaded_file: entry[:file], field: "candidate_document.files[#{index}].file")
        end
      end

      def build_blob(entry)
        tempfile = entry[:file].tempfile
        tempfile.rewind

        ActiveStorage::Blob.create_and_upload!(
          io: tempfile,
          filename: entry[:details].filename,
          content_type: entry[:details].content_type,
          identify: false
        )
      ensure
        tempfile&.rewind
      end

      def purge_blob(blob)
        return if blob.attachments.exists?

        blob.purge
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def persist_upload_and_advance_workflow(entries:, blobs:)
        ActiveRecord::Base.transaction do
          uploaded_document = UploadPersistence.call(
            candidate: @candidate,
            requirement:,
            files: entries.zip(blobs).map { |entry, blob| entry.slice(:side_code, :details).merge(blob:) },
            context: persistence_context
          )
          advance_workflow!
          uploaded_document
        end
      end

      def persistence_context
        { request_id: @request_id, issued_on: issued_on_for_persistence,
          next_of_kin_relation: (@next_of_kin_relation if next_of_kin_requirement?) }
      end

      # Only after the whole upload + workflow transaction has committed: Solid
      # Queue writes to its own database, so a job enqueued inside the
      # transaction would survive a rollback and run against a document that
      # was never saved. Only OCR-supported types (passport, CNIC, next-of-kin
      # CNIC) are extracted.
      def enqueue_extraction(document)
        return unless document.document_type.supports_ocr_extraction?
        return unless AppFeatureSetting.enabled?(:document_ocr)

        ExtractDatesJob.perform_later(document.id)
      end

      def pcc_issued_on
        @pcc_issued_on ||= PccIssueDateResolver.call(requirement:, issued_on: @issued_on)
      end

      def issued_on_for_persistence
        return unless pcc_requirement?

        pcc_issued_on
      end

      def advance_workflow!
        CandidateWorkflows::AutomaticTransitionService.call(
          candidate: @candidate,
          event: :documents_uploaded,
          request_id: @request_id
        )
      end

      def pcc_requirement?
        requirement.document_type.code == CandidateDocument::PCC_REQUIREMENT_CODE
      end

      def expires_on_supplied?(document_attributes)
        return document_attributes[:expires_on_supplied] if document_attributes.key?(:expires_on_supplied)

        document_attributes.key?(:expires_on)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
