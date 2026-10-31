# frozen_string_literal: true

# One row per send.pk message (the OTP and every progress SMS): its approved
# English and Urdu template ids and whether it is sent. Replaces the
# <MESSAGE>_TEMPLATE_ID env vars and AppFeatureSetting#disabled_sms_messages,
# so a developer can change both from App Settings without a deploy.
#
# The rows are filled once from the env vars and switches in place at deploy
# time; after that the env vars are no longer read and can be removed.
class CreateSmsTemplates < ActiveRecord::Migration[8.1]
  MESSAGE_CODES = %w[
    otp registered document_rejected medical_appointment fee_pending medical_unfit qvc_appointment
    visa_issued visa_rejected protection_call ticket_handover flight_details
  ].freeze

  def up
    create_sms_templates_table
    copy_existing_setup
    remove_column :app_feature_settings, :disabled_sms_messages
  end

  def down
    add_column :app_feature_settings, :disabled_sms_messages, :string, array: true, null: false, default: []
    execute <<~SQL.squish
      UPDATE app_feature_settings
      SET disabled_sms_messages = ARRAY(SELECT message_code FROM sms_templates WHERE NOT enabled)
    SQL
    drop_table :sms_templates
  end

  private

  def create_sms_templates_table
    create_table :sms_templates do |t|
      t.string :message_code, null: false, index: { unique: true }
      t.string :template_id_en
      t.string :template_id_ur
      t.boolean :enabled, null: false, default: true
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_check_constraints
  end

  def add_check_constraints
    add_check_constraint :sms_templates, "message_code IN (#{MESSAGE_CODES.map { |code| "'#{code}'" }.join(', ')})",
                         name: 'sms_templates_message_code_known'
    # Turning the OTP off would lock every candidate out of the app.
    add_check_constraint :sms_templates, "message_code <> 'otp' OR enabled", name: 'sms_templates_otp_always_enabled'
  end

  def copy_existing_setup
    disabled = select_values('SELECT unnest(disabled_sms_messages) FROM app_feature_settings')
    now = connection.quote(Time.current)

    MESSAGE_CODES.each do |code|
      values = [code, env_template_id(code, ''), env_template_id(code, '_UR'), disabled.exclude?(code)]
      execute <<~SQL.squish
        INSERT INTO sms_templates (message_code, template_id_en, template_id_ur, enabled, created_at, updated_at)
        VALUES (#{values.map { |value| connection.quote(value) }.join(', ')}, #{now}, #{now})
      SQL
    end
  end

  def env_template_id(code, suffix)
    ENV.fetch("#{code.upcase}_TEMPLATE_ID#{suffix}", '').strip.presence
  end
end
