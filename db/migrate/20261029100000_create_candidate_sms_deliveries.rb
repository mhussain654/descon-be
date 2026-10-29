# frozen_string_literal: true

# One progress SMS to a candidate (registered, medical date, visa issued, ...),
# sent through send.pk in the background. `dedupe_key` names the event the SMS is
# for, so the same event never sends twice; the row also keeps whether it went
# out, for admin and support.
class CreateCandidateSmsDeliveries < ActiveRecord::Migration[8.1]
  # One create_table block with its indexes and constraints reads best whole.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :candidate_sms_deliveries do |t|
      t.string :public_id, null: false
      t.references :candidate, null: false, foreign_key: true
      t.references :candidate_assignment, null: false, foreign_key: true
      t.string :message_code, null: false
      t.string :dedupe_key, null: false
      t.string :locale, null: false
      t.jsonb :variables, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.string :error_code
      t.string :provider_reference
      t.datetime :sent_at
      t.timestamps

      t.index :public_id, unique: true
      t.index :dedupe_key, unique: true
      t.index :status
      t.check_constraint "status IN ('pending', 'sent', 'failed', 'skipped')",
                         name: 'candidate_sms_deliveries_status_values'
      t.check_constraint "locale IN ('en', 'ur')", name: 'candidate_sms_deliveries_locale_values'
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
