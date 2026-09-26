# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::AgentConfigSync do
  let(:adapter) { instance_double(AiCalls::Providers::ElevenlabsAdapter) }
  let(:sync) { described_class.new(adapter:) }
  let(:baseline) { AiCalls::AgentConfigs::Baseline.for(:outbound) }

  before do
    allow(baseline).to receive(:agent_id).and_return('agent-out-1')
    allow(AiCalls::AgentConfigs::Baseline).to receive(:for).with(:outbound).and_return(baseline)
    allow(adapter).to receive(:update_agent_config)
  end

  describe '#check' do
    it 'reports the current agent config as in sync when it matches the canonical baseline' do
      allow(adapter).to receive(:fetch_agent_config).with(agent_id: 'agent-out-1').and_return(baseline.config)

      result = sync.check(:outbound)

      expect(result.role).to eq('outbound')
      expect(result.agent_id).to eq('agent-out-1')
      expect(result.in_sync).to be(true)
      expect(result.remote_digest).to eq(result.canonical_digest)
      expect(adapter).not_to have_received(:update_agent_config)
    end

    it 'reports drift when the published config differs from the baseline' do
      drifted = baseline.config.deep_merge('conversation_config' => { 'agent' => { 'language' => 'ur' } })
      allow(adapter).to receive(:fetch_agent_config).with(agent_id: 'agent-out-1').and_return(drifted)

      result = sync.check(:outbound)

      expect(result.in_sync).to be(false)
      expect(result.remote_digest).not_to eq(result.canonical_digest)
    end

    it 'raises when no agent id is configured for the role' do
      allow(baseline).to receive(:agent_id).and_return(nil)

      expect { sync.check(:outbound) }.to raise_error(AiCallProviderUnavailableError)
    end
  end

  describe '#sync!' do
    before do
      allow(adapter).to receive(:update_agent_config).and_return(baseline.config)
      allow(adapter).to receive(:fetch_agent_config).with(agent_id: 'agent-out-1').and_return(baseline.config)
    end

    context 'when outside production' do
      it 'pushes the canonical config and reports the result' do
        result = sync.sync!(:outbound)

        expect(adapter).to have_received(:update_agent_config).with(agent_id: 'agent-out-1', config: baseline.config)
        expect(result.in_sync).to be(true)
      end
    end

    context 'when in production' do
      before { allow(Rails.env).to receive(:production?).and_return(true) }

      it 'refuses without explicit confirmation' do
        expect { sync.sync!(:outbound) }.to raise_error(AiCalls::AgentConfigSyncError, /explicit confirmation/)
        expect(adapter).not_to have_received(:update_agent_config)
      end

      it 'refuses even with confirmation while the baseline prompt is still a placeholder' do
        expect do
          sync.sync!(:outbound, confirm_production: true)
        end.to raise_error(AiCalls::AgentConfigSyncError, /unapproved placeholder/)
        expect(adapter).not_to have_received(:update_agent_config)
      end

      it 'proceeds when confirmed and the baseline is no longer a placeholder' do
        allow(baseline).to receive(:placeholder?).and_return(false)

        expect { sync.sync!(:outbound, confirm_production: true) }.not_to raise_error
        expect(adapter).to have_received(:update_agent_config)
      end
    end
  end
end
