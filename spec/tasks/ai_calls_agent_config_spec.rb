# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'ai_calls:agent_config rake tasks' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task['ai_calls:agent_config:check'].reenable
    Rake::Task['ai_calls:agent_config:sync'].reenable
  end

  describe 'ai_calls:agent_config:check' do
    it 'requires a role argument' do
      expect { Rake::Task['ai_calls:agent_config:check'].invoke }.to raise_error(SystemExit)
    end

    it 'reports drift status for a configured role without writing anything' do
      configuration = instance_double(AiCalls::Configuration, elevenlabs_outbound_agent_id: 'agent-out-1')
      allow(AiCalls::Configuration).to receive(:new).and_return(configuration)
      baseline = AiCalls::AgentConfigs::Baseline.for(:outbound)
      adapter = instance_double(AiCalls::Providers::ElevenlabsAdapter, fetch_agent_config: baseline.config)
      allow(AiCalls::Providers::ElevenlabsAdapter).to receive(:new).and_return(adapter)

      expect do
        Rake::Task['ai_calls:agent_config:check'].invoke('outbound')
      end.to output(/OK: agent agent-out-1/).to_stdout
    end

    it 'aborts cleanly when no agent id is configured for the role' do
      configuration = instance_double(AiCalls::Configuration, elevenlabs_outbound_agent_id: nil)
      allow(AiCalls::Configuration).to receive(:new).and_return(configuration)

      expect { Rake::Task['ai_calls:agent_config:check'].invoke('outbound') }.to raise_error(SystemExit)
    end

    it 'reports drift when the published config does not match the canonical baseline' do
      configuration = instance_double(AiCalls::Configuration, elevenlabs_outbound_agent_id: 'agent-out-1')
      allow(AiCalls::Configuration).to receive(:new).and_return(configuration)
      baseline = AiCalls::AgentConfigs::Baseline.for(:outbound)
      drifted = baseline.config.deep_merge('conversation_config' => { 'agent' => { 'language' => 'ur' } })
      adapter = instance_double(AiCalls::Providers::ElevenlabsAdapter, fetch_agent_config: drifted)
      allow(AiCalls::Providers::ElevenlabsAdapter).to receive(:new).and_return(adapter)

      expect do
        Rake::Task['ai_calls:agent_config:check'].invoke('outbound')
      end.to output(/DRIFT: agent agent-out-1/).to_stdout
    end
  end

  describe 'ai_calls:agent_config:sync' do
    it 'requires a role argument' do
      expect { Rake::Task['ai_calls:agent_config:sync'].invoke }.to raise_error(SystemExit)
    end

    it 'refuses to run in production without explicit confirmation' do
      allow(Rails.env).to receive(:production?).and_return(true)
      configuration = instance_double(AiCalls::Configuration, elevenlabs_outbound_agent_id: 'agent-out-1')
      allow(AiCalls::Configuration).to receive(:new).and_return(configuration)

      expect { Rake::Task['ai_calls:agent_config:sync'].invoke('outbound') }.to raise_error(SystemExit)
    end

    it 'pushes the canonical baseline and reports success outside production' do
      configuration = instance_double(AiCalls::Configuration, elevenlabs_outbound_agent_id: 'agent-out-1')
      allow(AiCalls::Configuration).to receive(:new).and_return(configuration)
      baseline = AiCalls::AgentConfigs::Baseline.for(:outbound)
      adapter = instance_double(
        AiCalls::Providers::ElevenlabsAdapter, update_agent_config: baseline.config, fetch_agent_config: baseline.config
      )
      allow(AiCalls::Providers::ElevenlabsAdapter).to receive(:new).and_return(adapter)

      expect do
        Rake::Task['ai_calls:agent_config:sync'].invoke('outbound')
      end.to output(/Pushed baseline config to agent agent-out-1.*OK: agent agent-out-1/m).to_stdout
      expect(adapter).to have_received(:update_agent_config).with(agent_id: 'agent-out-1', config: baseline.config)
    end
  end
end
