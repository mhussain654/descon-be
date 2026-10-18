# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::RobocallConfiguration do
  subject(:configuration) { described_class.new }

  it 'reads the api key from the encrypted credentials for the current environment' do
    allow(Rails.application.credentials).to receive(:dig).with(:robocall, :test, :api_key).and_return('  key-1  ')
    expect(configuration.api_key).to eq('key-1')

    allow(Rails.application.credentials).to receive(:dig).with(:robocall, :test, :api_key).and_return(nil)
    expect(configuration.api_key).to be_nil
  end

  it 'defaults the endpoint and timeouts, and lets ENV override them' do
    expect(configuration.base_url).to eq('https://portal.robocall.pk')
    expect([configuration.open_timeout, configuration.read_timeout]).to eq([5, 10])
    expect(configuration.retry_window_minutes).to eq(30)

    with_env('ROBOCALL_BASE_URL' => 'https://portal.robocall.pk', 'ROBOCALL_OPEN_TIMEOUT_SECONDS' => '2',
             'ROBOCALL_READ_TIMEOUT_SECONDS' => '7', 'ROBOCALL_RETRY_WINDOW_MINUTES' => '45') do
      expect(configuration.base_url).to eq('https://portal.robocall.pk')
      expect([configuration.open_timeout, configuration.read_timeout]).to eq([2, 7])
      expect(configuration.retry_window_minutes).to eq(45)
    end
  end
end
