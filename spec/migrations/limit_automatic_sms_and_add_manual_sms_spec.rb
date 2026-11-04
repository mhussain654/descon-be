# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261104100000_limit_automatic_sms_and_add_manual_sms')

RSpec.describe LimitAutomaticSmsAndAddManualSms do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  around do |example|
    ActiveRecord::Migration.suppress_messages do
      migration.down
      example.run
    end
  ensure
    [CandidateSmsDelivery, SmsTemplate].each(&:reset_column_information)
  end

  def enabled_codes
    connection.select_values('SELECT message_code FROM sms_templates WHERE enabled ORDER BY message_code')
  end

  it 'sends only the three agreed SMS automatically, keeps the OTP on, and adds the permission' do
    described_class::OLD_CODES.each { |code| create(:sms_template, message_code: code, enabled: true) }
    ensure_staff_authorization_reference_data!

    migration.up

    expect(enabled_codes).to eq(%w[documents_submitted otp ticket_handover visa_issued])
    expect(connection.column_exists?(:candidate_sms_deliveries, :sent_by_id)).to be(true)
    expect(Role.find_by!(code: 'hr').permissions.pluck(:code)).to include('send_candidate_sms')
    expect(Role.find_by!(code: 'finance').permissions.pluck(:code)).not_to include('send_candidate_sms')
  end

  it 'reverses cleanly' do
    migration.up
    migration.down

    expect(connection.column_exists?(:candidate_sms_deliveries, :sent_by_id)).to be(false)
    expect(Permission.exists?(code: 'send_candidate_sms')).to be(false)
    migration.up
  end
end
