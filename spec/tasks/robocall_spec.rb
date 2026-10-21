# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'ai_calls:robocall rake tasks' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:console) { instance_double(AiCalls::RobocallConsole) }

  before do
    %w[check call multiple status].each { |name| Rake::Task["ai_calls:robocall:#{name}"].reenable }
    allow(AiCalls::RobocallConsole).to receive(:new).and_return(console)
  end

  describe 'ai_calls:robocall:check' do
    it 'prints the key check and balance' do
      allow(console).to receive(:check).and_return(['Key check: valid=true', 'Balance: "10"'])

      expect { Rake::Task['ai_calls:robocall:check'].invoke }.to output(/valid=true.*Balance: "10"/m).to_stdout
    end

    it 'aborts with a clear message when no api key is configured' do
      allow(console).to receive(:check).and_raise(AiCallProviderUnavailableError)

      expect { Rake::Task['ai_calls:robocall:check'].invoke }
        .to raise_error(SystemExit).and output(/api key is missing/).to_stderr
    end

    it 'aborts with the provider failure message when RoboCall cannot be reached' do
      allow(console).to receive(:check).and_raise(AiCallProviderRequestError)

      expect { Rake::Task['ai_calls:robocall:check'].invoke }
        .to raise_error(SystemExit).and output(/RoboCall request failed/).to_stderr
    end
  end

  describe 'ai_calls:robocall:call' do
    it 'requires both a voice id and a number, and places nothing without them' do
      allow(console).to receive(:place_call)

      expect { Rake::Task['ai_calls:robocall:call'].invoke('102') }.to raise_error(SystemExit)
      expect(console).not_to have_received(:place_call)
    end

    it 'places one call and prints the provider call id' do
      allow(console).to receive(:place_call).and_return(['Call placed. call_id="77"'])

      expect { Rake::Task['ai_calls:robocall:call'].invoke('102', '923001234567') }
        .to output(/call_id="77"/).to_stdout
      expect(console).to have_received(:place_call).with(voice_id: '102', number: '923001234567')
    end
  end

  describe 'ai_calls:robocall:multiple' do
    it 'needs a voice id and at least one number, and places nothing without them' do
      allow(console).to receive(:place_multiple)

      expect { Rake::Task['ai_calls:robocall:multiple'].invoke('102') }.to raise_error(SystemExit)
      expect(console).not_to have_received(:place_multiple)
    end

    it 'sends the space-separated numbers and prints the raw response' do
      allow(console).to receive(:place_multiple).and_return(['Response: {"status":200}'])

      expect { Rake::Task['ai_calls:robocall:multiple'].invoke('102', '923001234567 923007654321') }
        .to output(/Response/).to_stdout
      expect(console).to have_received(:place_multiple)
        .with(voice_id: '102', numbers: %w[923001234567 923007654321])
    end
  end

  describe 'ai_calls:robocall:status' do
    it 'requires a call id' do
      expect { Rake::Task['ai_calls:robocall:status'].invoke }.to raise_error(SystemExit)
    end

    it 'prints the status of one call' do
      allow(console).to receive(:status).and_return(['status_code=2 (answered) dtmf="1"'])

      expect { Rake::Task['ai_calls:robocall:status'].invoke('77') }.to output(/answered/).to_stdout
      expect(console).to have_received(:status).with(call_id: '77')
    end
  end
end
