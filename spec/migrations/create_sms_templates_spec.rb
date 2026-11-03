# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261030100000_create_sms_templates')

RSpec.describe CreateSmsTemplates do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  around do |example|
    ActiveRecord::Migration.suppress_messages do
      migration.down
      example.run
    end
  ensure
    [AppFeatureSetting, SmsTemplate].each(&:reset_column_information)
  end

  before do
    connection.execute(<<~SQL.squish)
      INSERT INTO app_feature_settings (disabled_sms_messages, created_at, updated_at)
      VALUES ('{fee_pending}', NOW(), NOW())
      ON CONFLICT (singleton_guard) DO UPDATE SET disabled_sms_messages = EXCLUDED.disabled_sms_messages
    SQL
    stub_const('ENV', ENV.to_h.merge('OTP_TEMPLATE_ID' => '11062', 'OTP_TEMPLATE_ID_UR' => ' ',
                                     'REGISTERED_TEMPLATE_ID' => '20001', 'REGISTERED_TEMPLATE_ID_UR' => '20002'))
  end

  def row(code)
    connection.select_one(
      "SELECT template_id_en, template_id_ur, enabled FROM sms_templates WHERE message_code = '#{code}'"
    )
  end

  describe '#up' do
    it 'fills one row per message from the template env vars and the per-message switches' do
      migration.up

      expect(connection.select_value('SELECT COUNT(*) FROM sms_templates')).to eq(SmsTemplate::MESSAGE_CODES.size)
      expect(row('otp')).to eq('template_id_en' => '11062', 'template_id_ur' => nil, 'enabled' => true)
      expect(row('registered')).to eq('template_id_en' => '20001', 'template_id_ur' => '20002', 'enabled' => true)
      expect(row('fee_pending')).to eq('template_id_en' => nil, 'template_id_ur' => nil, 'enabled' => false)
      expect(connection.column_exists?(:app_feature_settings, :disabled_sms_messages)).to be(false)
    end
  end

  describe '#down' do
    it 'puts the switched-off messages back on the feature settings row' do
      migration.up
      connection.execute("UPDATE sms_templates SET enabled = FALSE WHERE message_code = 'visa_issued'")

      migration.down

      expect(connection.select_value('SELECT disabled_sms_messages FROM app_feature_settings'))
        .to eq('{fee_pending,visa_issued}')
      expect(connection.table_exists?(:sms_templates)).to be(false)
      migration.up
    end
  end
end
