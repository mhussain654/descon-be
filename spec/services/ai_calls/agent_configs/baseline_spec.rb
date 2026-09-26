# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::AgentConfigs::Baseline do
  describe '.for' do
    it 'builds a baseline for a known role' do
      expect(described_class.for(:outbound)).to be_a(described_class)
      expect(described_class.for('inbound').role).to eq('inbound')
    end

    it 'rejects an unknown role' do
      expect { described_class.for(:unknown) }.to raise_error(ArgumentError, /unknown AI call agent role/)
    end
  end

  describe '#agent_id' do
    it 'reads the configured agent id for its role' do
      configuration = instance_double(AiCalls::Configuration, elevenlabs_outbound_agent_id: 'agent-out-1')

      expect(described_class.for(:outbound).agent_id(configuration:)).to eq('agent-out-1')
    end
  end

  describe '#placeholder?' do
    it 'is true for the currently unapproved baseline prompts' do
      expect(described_class.for(:outbound)).to be_placeholder
      expect(described_class.for(:inbound)).to be_placeholder
    end
  end

  describe '#config and #digest' do
    it 'includes the role-specific prompt and only the managed top-level keys' do
      config = described_class.for(:outbound).config

      expect(config.keys).to match_array(%w[name conversation_config])
      expect(config.dig('conversation_config', 'agent', 'prompt', 'prompt')).to include('outbound call')
    end

    it 'produces a stable digest independent of hash key order' do
      baseline = described_class.for(:outbound)
      reordered_config = baseline.config.to_a.reverse.to_h

      expect(baseline.digest).to eq(Digest::SHA256.hexdigest(JSON.generate(deep_sort(reordered_config))))
    end

    it 'differs between outbound and inbound baselines' do
      expect(described_class.for(:outbound).digest).not_to eq(described_class.for(:inbound).digest)
    end

    it 'sets first_message to the inbound opening line, but not for outbound' do
      inbound_config = described_class.for(:inbound).config
      outbound_config = described_class.for(:outbound).config

      expect(inbound_config.dig('conversation_config', 'agent', 'first_message')).to include('Descon Manpower')
      expect(outbound_config.dig('conversation_config', 'agent')).not_to have_key('first_message')
    end
  end

  describe 'transfer_to_number built-in tool' do
    def configuration_double(enabled:, number:)
      instance_double(AiCalls::Configuration, human_transfer_enabled?: enabled, human_transfer_phone_number: number)
    end

    it 'is omitted when human transfer is disabled, even with a number configured' do
      configuration = configuration_double(enabled: false, number: '+923001234567')

      config = described_class.for(:outbound).config(configuration:)

      expect(config.dig('conversation_config', 'agent', 'prompt')).not_to have_key('built_in_tools')
    end

    it 'is omitted when enabled but no destination number is configured' do
      configuration = configuration_double(enabled: true, number: nil)

      config = described_class.for(:outbound).config(configuration:)

      expect(config.dig('conversation_config', 'agent', 'prompt')).not_to have_key('built_in_tools')
    end

    it 'is included, targeting the configured number, once enabled with a number set' do
      configuration = configuration_double(enabled: true, number: '+923001234567')

      config = described_class.for(:outbound).config(configuration:)

      tool = config.dig('conversation_config', 'agent', 'prompt', 'built_in_tools', 'transfer_to_number')
      expect(tool.dig('params', 'system_tool_type')).to eq('transfer_to_number')
      transfer = tool.dig('params', 'transfers', 0)
      expect(transfer.dig('transfer_destination', 'phone_number')).to eq('+923001234567')
      expect(transfer['transfer_type']).to eq('conference')
    end

    it 'is included on both outbound and inbound baselines' do
      configuration = configuration_double(enabled: true, number: '+923001234567')

      %i[outbound inbound].each do |role|
        config = described_class.for(role).config(configuration:)
        expect(config.dig('conversation_config', 'agent', 'prompt', 'built_in_tools')).to have_key('transfer_to_number')
      end
    end

    it 'changes the digest once it becomes included' do
      baseline = described_class.for(:outbound)
      without_transfer = configuration_double(enabled: false, number: nil)
      with_transfer = configuration_double(enabled: true, number: '+923001234567')

      expect(baseline.digest(configuration: without_transfer)).not_to eq(baseline.digest(configuration: with_transfer))
    end
  end

  describe '#digest_for_remote' do
    it 'ignores unmanaged fields the provider echoes back' do
      baseline = described_class.for(:outbound)
      remote_config = baseline.config.merge('agent_id' => 'agent-out-1', 'updated_at' => '2026-09-10T00:00:00Z')

      expect(baseline.digest_for_remote(remote_config)).to eq(baseline.digest)
    end

    it 'detects drift in a managed field' do
      baseline = described_class.for(:outbound)
      drifted = baseline.config.deep_merge('conversation_config' => { 'agent' => { 'language' => 'ur' } })

      expect(baseline.digest_for_remote(drifted)).not_to eq(baseline.digest)
    end
  end

  def deep_sort(value)
    case value
    when Hash
      value.sort.to_h { |key, nested| [key, deep_sort(nested)] }
    when Array
      value.map { |nested| deep_sort(nested) }
    else
      value
    end
  end
end
