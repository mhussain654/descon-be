# frozen_string_literal: true

# The single admin-editable row of feature switches (card payment, payment
# code, progress SMS and each of its messages, automatic and bulk calls,
# document auto-read). Same singleton shape as SupportSetting: `singleton_guard`
# is always true and its unique index makes a second row impossible. Every
# switch starts on: a feature still runs only when its server setup is also in
# place, so turning it on here never switches on something unconfigured.
class CreateAppFeatureSettings < ActiveRecord::Migration[8.1]
  # rubocop:disable Metrics/MethodLength -- one create_table block, one column per switch
  def change
    create_table :app_feature_settings do |t|
      t.boolean :singleton_guard, null: false, default: true
      t.boolean :card_payment_enabled, null: false, default: true
      t.boolean :voucher_payment_enabled, null: false, default: true
      t.boolean :progress_sms_enabled, null: false, default: true
      t.string :disabled_sms_messages, array: true, null: false, default: []
      t.boolean :automatic_calls_enabled, null: false, default: true
      t.boolean :bulk_calls_enabled, null: false, default: true
      t.boolean :document_ocr_enabled, null: false, default: true
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :app_feature_settings, :singleton_guard, unique: true
  end
  # rubocop:enable Metrics/MethodLength
end
