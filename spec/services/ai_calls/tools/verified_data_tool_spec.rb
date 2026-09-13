# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::VerifiedDataTool do
  let(:concrete_tool_class) do
    Class.new(described_class) do
      def data = { ok: true }
    end
  end

  it 'refuses inbound calls that are not yet verified' do
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'pending')

    expect(concrete_tool_class.call(candidate_ai_call: call_record)).to eq(error: 'not_verified')
  end

  it 'allows inbound calls once verified, with an assignment present' do
    assignment = create(:candidate_assignment)
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate: assignment.candidate,
                                                       candidate_assignment: assignment)

    expect(concrete_tool_class.call(candidate_ai_call: call_record)).to eq(ok: true)
  end

  it 'allows outbound calls with not_applicable/skipped verification, without an OTP-style check' do
    %w[not_applicable skipped].each do |status|
      call_record = create(:candidate_ai_call, verification_status: status)

      expect(concrete_tool_class.call(candidate_ai_call: call_record)).to eq(ok: true)
    end
  end

  it 'refuses a verified inbound call that has no linked assignment yet' do
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified')

    expect(concrete_tool_class.call(candidate_ai_call: call_record)).to eq(error: 'no_assignment')
  end
end
