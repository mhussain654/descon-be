# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetFlightInformation do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:call_record) do
    create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:, candidate_assignment: assignment)
  end

  it 'returns not_yet_available when no flight detail exists' do
    expect(described_class.call(candidate_ai_call: call_record)).to eq(status: 'not_yet_available')
  end

  it 'returns the flight detail when one exists' do
    detail = create(:candidate_flight_detail, candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:id]).to eq(detail.public_id)
    expect(result[:airline]).to eq('Qatar Airways')
  end
end
