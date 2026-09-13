# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetProtectionStatus do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:call_record) do
    create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:, candidate_assignment: assignment)
  end

  it 'returns not_yet_scheduled when no protection record exists' do
    expect(described_class.call(candidate_ai_call: call_record)).to eq(status: 'not_yet_scheduled')
  end

  it 'returns the protection record when one exists' do
    record = create(:candidate_protection_record, candidate_assignment: assignment, appeared_on: Date.current,
                                                  appeared_recorded_at: Time.current,
                                                  appeared_recorded_by: assignment.created_by)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:id]).to eq(record.public_id)
    expect(result[:appeared_on]).to eq(record.appeared_on.iso8601)
  end
end
