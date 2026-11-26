# frozen_string_literal: true

module Maintenance
  # One-off pre-launch cleanup: removes every candidate and all test activity
  # (documents and their files, payments, SMS/communications, AI calls,
  # imports, stage history, the whole audit log) and every staff account
  # except the developer role, while keeping configuration: roles and
  # permissions, reference catalogs, workflow stages and processes, document
  # checklists, every admin setting, SMS templates, call scripts, robocall
  # voices, training videos and database backups.
  #
  # Staff references on kept rows (e.g. a setting's `updated_by_id`) are
  # pointed at the first active developer before the other staff are
  # deleted. Database rows are deleted in one transaction; the files of the
  # deleted records are purged from storage only after it commits. Run
  # `db:seed` afterwards to recreate the store reviewer candidate.
  # See docs/prelaunch-data-reset.md.
  class PrelaunchDataReset
    class NotAllowedError < StandardError
    end

    CONFIRMATION = 'DELETE-ALL-TEST-DATA'
    KEPT_STAFF_ROLE = 'developer'

    # Emptied completely. Ordered at run time from the database's own foreign
    # keys, so each table is emptied before the tables it references.
    PURGED_TABLES = %w[
      candidates candidate_assignments candidate_consents candidate_bank_details
      candidate_documents candidate_document_files document_extractions
      candidate_document_submissions candidate_document_submission_items
      candidate_flight_details candidate_medical_results candidate_protection_records candidate_qvc_attempts
      candidate_visa_decisions candidate_stage_histories candidate_stage_history_corrections
      candidate_workflow_events candidate_otp_challenges candidate_sessions candidate_refresh_tokens
      candidate_sms_deliveries communications
      candidate_ai_calls candidate_ai_call_events candidate_ai_call_transcripts bulk_call_batches bulk_call_batch_items
      candidate_import_batches candidate_import_row_results
      payments payment_events payment_reconciliation_runs payment_reconciliation_findings
      audit_events idempotency_keys
      authentication_events sessions refresh_tokens
    ].freeze

    # Models of purged tables that carry Active Storage files.
    PURGED_ATTACHMENT_RECORD_TYPES = %w[
      Candidate CandidateBankDetail CandidateDocumentFile CandidateFlightDetail CandidateVisaDecision
    ].freeze

    Summary = Data.define(:table_counts, :kept_staff, :removed_staff_count, :keeper, :attachment_count)

    def self.preview = new.preview

    def self.call(confirmation:) = new.call(confirmation:)

    # What a run would delete and keep. Changes nothing.
    def preview
      Summary.new(
        table_counts:,
        kept_staff: kept_staff.order(:created_at).pluck(:email),
        removed_staff_count: User.where.not(role: KEPT_STAFF_ROLE).count,
        keeper: keeper&.email,
        attachment_count: purged_attachments.count
      )
    end

    def call(confirmation:)
      ensure_allowed!(confirmation)
      summary = preview
      blob_ids = purged_attachments.pluck(:blob_id)
      ActiveRecord::Base.transaction { delete_test_data! }
      purge_unattached_blobs(blob_ids)
      summary
    end

    # Rows a run deletes per purged table, plus the campaigns made while testing.
    def table_counts
      ordered_tables.index_with { |table| row_count(table) }.merge('campaigns' => Campaign.regular.count)
    end

    # Purged tables, children first.
    def ordered_tables
      @ordered_tables ||= PurgedTableOrder.new(PURGED_TABLES).ordered
    end

    # Kept tables that reference a purged table: must be none, or the run
    # would fail. Checked by the spec, so a new table gets a decision.
    def kept_tables_referencing_purged = PurgedTableOrder.new(PURGED_TABLES).outside_references

    private

    def connection = ActiveRecord::Base.connection

    def row_count(table) = connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)}").to_i

    def ensure_allowed!(confirmation)
      raise NotAllowedError, "Type #{CONFIRMATION} to confirm." unless confirmation == CONFIRMATION
      raise NotAllowedError, 'No active developer account: one must remain to own the kept settings.' unless keeper
    end

    def delete_test_data!
      purged_attachments.delete_all
      ordered_tables.each { |table| connection.execute("DELETE FROM #{connection.quote_table_name(table)}") }
      remove_test_campaigns!
      reassign_staff_references!
      remove_other_staff!
    end

    def kept_staff = User.where(role: KEPT_STAFF_ROLE)

    def keeper
      @keeper ||= kept_staff.where(active: true).order(:created_at).first
    end

    def purged_attachments
      ActiveStorage::Attachment.where(record_type: PURGED_ATTACHMENT_RECORD_TYPES)
    end

    # Every kept row that names a staff member who is about to be removed now
    # names the keeper instead; `users.invited_by_id` is cleared.
    def reassign_staff_references!
      removed_ids = User.where.not(role: KEPT_STAFF_ROLE).select(:id)
      staff_reference_columns.each do |table, column|
        model_free_update(table, column, keeper.id, removed_ids)
      end
      User.where(invited_by_id: removed_ids).update_all(invited_by_id: nil) # rubocop:disable Rails/SkipsModelValidations
    end

    def staff_reference_columns
      (connection.tables - PURGED_TABLES - ['users']).flat_map do |table|
        connection.foreign_keys(table).select { |key| key.to_table == 'users' }.map { |key| [table, key.column] }
      end
    end

    # A throwaway model for a table, so the update goes through Active Record's
    # query builder rather than hand-written SQL.
    def model_free_update(table, column, keeper_id, removed_ids)
      model = Class.new(ApplicationRecord) { self.table_name = table }
      model.where(column => removed_ids).update_all(column => keeper_id) # rubocop:disable Rails/SkipsModelValidations
    end

    # Campaigns made while testing go; the built-in Test campaign stays for the
    # store reviewer. Staff whose running campaign was removed fall back to all
    # campaigns (users.selected_campaign_id is ON DELETE SET NULL).
    def remove_test_campaigns!
      Campaign.regular.delete_all
    end

    def remove_other_staff!
      User.where.not(role: KEPT_STAFF_ROLE).delete_all
    end

    # Deletes the stored files (and blob rows) the removed records used,
    # skipping any blob still attached to a kept record.
    def purge_unattached_blobs(blob_ids)
      ActiveStorage::Blob.where(id: blob_ids).where.missing(:attachments).find_each(&:purge)
    end
  end
end
