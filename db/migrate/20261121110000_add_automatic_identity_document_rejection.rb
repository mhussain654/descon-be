# frozen_string_literal: true

# Automatic rejection of a CNIC or passport upload that clearly isn't one (a
# selfie, a random photo, another document), behind a developer-only App
# Settings switch that starts off. A system rejection has no staff reviewer, so
# the status check allows a rejected row without verified_by when it was
# rejected automatically.
class AddAutomaticIdentityDocumentRejection < ActiveRecord::Migration[8.1]
  STATUS_CHECK = 'candidate_documents_status_consistency'

  OLD_STATUS_RULE = <<~SQL.squish
    (status_code IN ('uploaded', 'under_verification') AND verified_by_id IS NULL AND verified_at IS NULL
      AND rejection_reason IS NULL)
    OR (status_code = 'verified' AND verified_by_id IS NOT NULL AND verified_at IS NOT NULL
      AND rejection_reason IS NULL)
    OR (status_code = 'rejected' AND verified_by_id IS NOT NULL AND verified_at IS NOT NULL
      AND rejection_reason IS NOT NULL)
  SQL

  NEW_STATUS_RULE = <<~SQL.squish
    (status_code IN ('uploaded', 'under_verification') AND verified_by_id IS NULL AND verified_at IS NULL
      AND rejection_reason IS NULL AND NOT rejected_automatically)
    OR (status_code = 'verified' AND verified_by_id IS NOT NULL AND verified_at IS NOT NULL
      AND rejection_reason IS NULL AND NOT rejected_automatically)
    OR (status_code = 'rejected' AND verified_at IS NOT NULL AND rejection_reason IS NOT NULL
      AND (verified_by_id IS NOT NULL OR rejected_automatically))
  SQL

  def change
    add_column :app_feature_settings, :document_identity_check_enabled, :boolean, null: false, default: false
    add_column :candidate_documents, :rejected_automatically, :boolean, null: false, default: false
    add_column :document_extractions, :identity_check, :string
    add_check_constraint :document_extractions,
                         "identity_check IS NULL OR identity_check IN ('identity_document', 'other_text', 'no_text')",
                         name: 'document_extractions_identity_check'

    reversible do |direction|
      direction.up { replace_status_check(NEW_STATUS_RULE) }
      direction.down { replace_status_check(OLD_STATUS_RULE) }
    end
  end

  private

  def replace_status_check(rule)
    remove_check_constraint :candidate_documents, name: STATUS_CHECK
    add_check_constraint :candidate_documents, rule, name: STATUS_CHECK
  end
end
