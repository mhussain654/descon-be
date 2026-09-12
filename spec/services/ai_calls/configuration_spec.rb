# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Configuration do
  around do |example|
    original_env = ENV.to_h
    example.run
  ensure
    ENV.replace(original_env)
  end

  it 'returns safe defaults in test' do
    ENV.delete('ELEVENLABS_API_KEY')
    ENV.delete('ELEVENLABS_BASE_URL')
    ENV.delete('ELEVENLABS_OUTBOUND_AGENT_ID')
    ENV.delete('ELEVENLABS_INBOUND_AGENT_ID')
    ENV.delete('ELEVENLABS_AGENT_PHONE_NUMBER_ID')
    ENV.delete('ELEVENLABS_WEBHOOK_SIGNING_SECRET')
    ENV.delete('ELEVENLABS_OPEN_TIMEOUT_SECONDS')
    ENV.delete('ELEVENLABS_READ_TIMEOUT_SECONDS')
    ENV.delete('AI_CALLS_TOOL_SHARED_SECRET')
    ENV.delete('TWILIO_ACCOUNT_SID')
    ENV.delete('TWILIO_AUTH_TOKEN')
    ENV.delete('TWILIO_BASE_URL')
    ENV.delete('TWILIO_OPEN_TIMEOUT_SECONDS')
    ENV.delete('TWILIO_READ_TIMEOUT_SECONDS')
    ENV.delete('AI_VOICE_OUTBOUND_ENABLED')
    ENV.delete('AI_VOICE_INBOUND_ENABLED')
    ENV.delete('AI_VOICE_RECORDING_ENABLED')
    ENV.delete('AI_VOICE_HUMAN_TRANSFER_ENABLED')
    ENV.delete('AI_VOICE_OUTBOUND_TRIGGER_COOLDOWN_MINUTES')
    ENV.delete('AI_VOICE_DAILY_OUTBOUND_CALL_LIMIT')
    ENV.delete('AI_VOICE_ADMIN_TRIGGER_RATE_LIMIT_PER_HOUR')
    ENV.delete('AI_VOICE_CALLING_HOURS_START')
    ENV.delete('AI_VOICE_CALLING_HOURS_END')
    ENV.delete('AI_VOICE_MAX_CALL_DURATION_MINUTES')
    ENV.delete('AI_VOICE_TRANSCRIPT_RETENTION_DAYS')

    configuration = described_class.new

    expect(configuration.elevenlabs_api_key).to be_nil
    expect(configuration.elevenlabs_base_url).to eq('https://api.elevenlabs.io')
    expect(configuration.elevenlabs_outbound_agent_id).to be_nil
    expect(configuration.elevenlabs_inbound_agent_id).to be_nil
    expect(configuration.elevenlabs_agent_phone_number_id).to be_nil
    expect(configuration.elevenlabs_webhook_signing_secret).to be_nil
    expect(configuration.elevenlabs_open_timeout).to eq(5)
    expect(configuration.elevenlabs_read_timeout).to eq(15)
    expect(configuration.tool_shared_secret).to be_nil
    expect(configuration.twilio_account_sid).to be_nil
    expect(configuration.twilio_auth_token).to be_nil
    expect(configuration.twilio_base_url).to eq('https://api.twilio.com')
    expect(configuration.twilio_open_timeout).to eq(5)
    expect(configuration.twilio_read_timeout).to eq(10)
    expect(configuration.outbound_enabled?).to be(false)
    expect(configuration.inbound_enabled?).to be(false)
    expect(configuration.recording_enabled?).to be(false)
    expect(configuration.human_transfer_enabled?).to be(false)
    expect(configuration.outbound_trigger_cooldown_minutes).to eq(60)
    expect(configuration.daily_outbound_call_limit).to eq(200)
    expect(configuration.admin_trigger_rate_limit_per_hour).to eq(50)
    expect(configuration.calling_hours_start).to eq(9)
    expect(configuration.calling_hours_end).to eq(19)
    expect(configuration.max_call_duration_minutes).to eq(15)
    expect(configuration.transcript_retention_days).to eq(90)
  end

  it 'normalizes configured environment values' do
    ENV['ELEVENLABS_API_KEY'] = ' elevenlabs-key '
    ENV['ELEVENLABS_BASE_URL'] = ' https://elevenlabs.example.test '
    ENV['ELEVENLABS_OUTBOUND_AGENT_ID'] = ' outbound-agent-1 '
    ENV['ELEVENLABS_INBOUND_AGENT_ID'] = ' inbound-agent-1 '
    ENV['ELEVENLABS_AGENT_PHONE_NUMBER_ID'] = ' phone-number-1 '
    ENV['ELEVENLABS_WEBHOOK_SIGNING_SECRET'] = ' webhook-secret '
    ENV['ELEVENLABS_OPEN_TIMEOUT_SECONDS'] = '7'
    ENV['ELEVENLABS_READ_TIMEOUT_SECONDS'] = '20'
    ENV['AI_CALLS_TOOL_SHARED_SECRET'] = ' tool-secret '
    ENV['TWILIO_ACCOUNT_SID'] = ' account-sid '
    ENV['TWILIO_AUTH_TOKEN'] = ' auth-token '
    ENV['TWILIO_BASE_URL'] = ' https://twilio.example.test '
    ENV['TWILIO_OPEN_TIMEOUT_SECONDS'] = '8'
    ENV['TWILIO_READ_TIMEOUT_SECONDS'] = '18'
    ENV['AI_VOICE_OUTBOUND_ENABLED'] = 'true'
    ENV['AI_VOICE_INBOUND_ENABLED'] = 'true'
    ENV['AI_VOICE_RECORDING_ENABLED'] = 'true'
    ENV['AI_VOICE_HUMAN_TRANSFER_ENABLED'] = 'true'
    ENV['AI_VOICE_OUTBOUND_TRIGGER_COOLDOWN_MINUTES'] = '30'
    ENV['AI_VOICE_DAILY_OUTBOUND_CALL_LIMIT'] = '75'
    ENV['AI_VOICE_ADMIN_TRIGGER_RATE_LIMIT_PER_HOUR'] = '20'
    ENV['AI_VOICE_CALLING_HOURS_START'] = '8'
    ENV['AI_VOICE_CALLING_HOURS_END'] = '20'
    ENV['AI_VOICE_MAX_CALL_DURATION_MINUTES'] = '25'
    ENV['AI_VOICE_TRANSCRIPT_RETENTION_DAYS'] = '45'

    configuration = described_class.new

    expect(configuration.elevenlabs_api_key).to eq('elevenlabs-key')
    expect(configuration.elevenlabs_base_url).to eq('https://elevenlabs.example.test')
    expect(configuration.elevenlabs_outbound_agent_id).to eq('outbound-agent-1')
    expect(configuration.elevenlabs_inbound_agent_id).to eq('inbound-agent-1')
    expect(configuration.elevenlabs_agent_phone_number_id).to eq('phone-number-1')
    expect(configuration.elevenlabs_webhook_signing_secret).to eq('webhook-secret')
    expect(configuration.elevenlabs_open_timeout).to eq(7)
    expect(configuration.elevenlabs_read_timeout).to eq(20)
    expect(configuration.tool_shared_secret).to eq('tool-secret')
    expect(configuration.twilio_account_sid).to eq('account-sid')
    expect(configuration.twilio_auth_token).to eq('auth-token')
    expect(configuration.twilio_base_url).to eq('https://twilio.example.test')
    expect(configuration.twilio_open_timeout).to eq(8)
    expect(configuration.twilio_read_timeout).to eq(18)
    expect(configuration.outbound_enabled?).to be(true)
    expect(configuration.inbound_enabled?).to be(true)
    expect(configuration.recording_enabled?).to be(true)
    expect(configuration.human_transfer_enabled?).to be(true)
    expect(configuration.outbound_trigger_cooldown_minutes).to eq(30)
    expect(configuration.daily_outbound_call_limit).to eq(75)
    expect(configuration.admin_trigger_rate_limit_per_hour).to eq(20)
    expect(configuration.calling_hours_start).to eq(8)
    expect(configuration.calling_hours_end).to eq(20)
    expect(configuration.max_call_duration_minutes).to eq(25)
    expect(configuration.transcript_retention_days).to eq(45)
  end

  it 'treats blank strings as absent for presence-checked values' do
    ENV['ELEVENLABS_API_KEY'] = '   '

    expect(described_class.new.elevenlabs_api_key).to be_nil
  end

  describe 'the 5 DB-editable operational knobs' do
    it 'falls back to ENV when the AiCallOperationalSetting row has every column nil' do
      AiCallOperationalSetting.current

      configuration = described_class.new

      expect(configuration.outbound_trigger_cooldown_minutes).to eq(60)
      expect(configuration.daily_outbound_call_limit).to eq(200)
      expect(configuration.admin_trigger_rate_limit_per_hour).to eq(50)
      expect(configuration.calling_hours_start).to eq(9)
      expect(configuration.calling_hours_end).to eq(19)
      expect(configuration.max_call_duration_minutes).to eq(15)
    end

    it 'prefers the DB row over ENV when a column is set' do
      AiCallOperationalSetting.current.update!(
        outbound_trigger_cooldown_minutes: 10, daily_outbound_call_limit: 5,
        admin_trigger_rate_limit_per_hour: 3, calling_hours_start: 7, calling_hours_end: 21,
        max_call_duration_minutes: 8
      )
      ENV['AI_VOICE_OUTBOUND_TRIGGER_COOLDOWN_MINUTES'] = '999'

      configuration = described_class.new

      expect(configuration.outbound_trigger_cooldown_minutes).to eq(10)
      expect(configuration.daily_outbound_call_limit).to eq(5)
      expect(configuration.admin_trigger_rate_limit_per_hour).to eq(3)
      expect(configuration.calling_hours_start).to eq(7)
      expect(configuration.calling_hours_end).to eq(21)
      expect(configuration.max_call_duration_minutes).to eq(8)
    end

    it 'falls back to ENV per-column when only some DB columns are set' do
      AiCallOperationalSetting.current.update!(daily_outbound_call_limit: 5)

      configuration = described_class.new

      expect(configuration.daily_outbound_call_limit).to eq(5)
      expect(configuration.outbound_trigger_cooldown_minutes).to eq(60)
    end

    it 'lazily creates the AiCallOperationalSetting row if none exists yet' do
      expect(AiCallOperationalSetting.count).to eq(0)

      described_class.new.daily_outbound_call_limit

      expect(AiCallOperationalSetting.count).to eq(1)
    end
  end
end
