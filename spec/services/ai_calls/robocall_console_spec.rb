# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::RobocallConsole do
  let(:adapter) { instance_double(AiCalls::Providers::RobocallAdapter) }
  let(:console) { described_class.new(adapter:) }

  it 'reports whether the key is valid and the remaining balance' do
    allow(adapter).to receive_messages(
      verify_key: { 'valid' => true, 'message' => 'ok' },
      check_balance: { 'data' => { 'balance' => '1500', 'call_rate' => '2' } }
    )

    expect(console.check).to eq(['Key check: valid=true message="ok"', 'Balance: "1500" (call rate: "2")'])
  end

  it 'copes with a balance response that has no data section' do
    allow(adapter).to receive_messages(verify_key: {}, check_balance: {})

    expect(console.check.last).to eq('Balance: nil (call rate: nil)')
  end

  it 'places one call and reports the provider call id' do
    result = AiCalls::Providers::RobocallAdapter::CallResult.new(call_id: '77')
    allow(adapter).to receive(:initiate_call).and_return(result)

    expect(console.place_call(voice_id: '102', number: '923001234567')).to eq(['Call placed. call_id="77"'])
    expect(adapter).to have_received(:initiate_call).with(voice_id: '102', to_number: '923001234567')
  end

  it 'prints RoboCall\'s raw response to a multiple-calls request' do
    allow(adapter).to receive(:initiate_multiple_calls_raw).and_return({ 'status' => 200,
                                                                         'data' => [{ 'call_id' => 1 }] })

    expect(console.place_multiple(voice_id: '102', numbers: %w[923001234567 923007654321]))
      .to eq(['Response: {"status":200,"data":[{"call_id":1}]}'])
    expect(adapter).to have_received(:initiate_multiple_calls_raw)
      .with(voice_id: '102', to_numbers: %w[923001234567 923007654321])
  end

  it 'names the status code and shows the key pressed' do
    allow(adapter).to receive(:fetch_call)
      .and_return(AiCalls::Providers::RobocallAdapter::CallStatus.new(status_code: 2, dtmf: '3'))
    expect(console.status(call_id: '77')).to eq(['status_code=2 (answered) dtmf="3"'])

    allow(adapter).to receive(:fetch_call)
      .and_return(AiCalls::Providers::RobocallAdapter::CallStatus.new(status_code: nil, dtmf: nil))
    expect(console.status(call_id: '77')).to eq(['status_code=nil (unknown) dtmf=nil'])
  end
end
