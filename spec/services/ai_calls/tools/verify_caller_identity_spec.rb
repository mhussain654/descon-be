# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::VerifyCallerIdentity do
  let(:candidate) { create(:candidate, mobile_number: '+923001234512', cnic: '42101-1234567-1') }
  let(:assignment) { create(:candidate_assignment, candidate:) }

  def call_for(caller_number:)
    create(:candidate_ai_call, :inbound, caller_number:)
  end

  it 'verifies immediately when the reference number resolves and the caller number matches' do
    call_record = call_for(caller_number: candidate.mobile_number)

    result = described_class.call(candidate_ai_call: call_record,
                                  params: { 'reference_number' => assignment.reference_number })

    expect(result.verified).to be(true)
    expect(call_record.reload.verification_status).to eq('verified')
    expect(call_record.candidate).to eq(candidate)
  end

  it 'asks for CNIC when the caller number does not match' do
    call_record = call_for(caller_number: '+929999999999')

    result = described_class.call(candidate_ai_call: call_record,
                                  params: { 'reference_number' => assignment.reference_number })

    expect(result.verified).to be(false)
    expect(result.additional_verification_required).to eq('cnic')
    expect(call_record.reload.verification_status).to eq('pending')
  end

  it 'verifies with a matching CNIC when the caller number does not match' do
    call_record = call_for(caller_number: '+929999999999')

    result = described_class.call(
      candidate_ai_call: call_record,
      params: { 'reference_number' => assignment.reference_number, 'cnic' => '42101-1234567-1' }
    )

    expect(result.verified).to be(true)
  end

  it 'fails with an unknown reference number, consuming an attempt' do
    call_record = call_for(caller_number: '+929999999999')

    result = described_class.call(candidate_ai_call: call_record, params: { 'reference_number' => 'BOGUS-1' })

    expect(result.verified).to be(false)
    expect(result.locked).to be_nil
    expect(call_record.reload.verification_attempts).to eq(1)
  end

  it 'fails with a mismatched CNIC, consuming an attempt' do
    call_record = call_for(caller_number: '+929999999999')

    result = described_class.call(
      candidate_ai_call: call_record,
      params: { 'reference_number' => assignment.reference_number, 'cnic' => '11111-1111111-1' }
    )

    expect(result.verified).to be(false)
    expect(call_record.reload.verification_attempts).to eq(1)
  end

  it 'locks after MAX_ATTEMPTS failed attempts' do
    call_record = call_for(caller_number: '+929999999999')

    described_class::MAX_ATTEMPTS.times do
      described_class.call(candidate_ai_call: call_record, params: { 'reference_number' => 'BOGUS-1' })
    end
    result = described_class.call(candidate_ai_call: call_record, params: { 'reference_number' => 'BOGUS-1' })

    expect(result.verified).to be(false)
    expect(result.locked).to be(true)
    expect(call_record.reload.verification_status).to eq('failed')
  end

  it 'short-circuits to verified: true once already verified, without consuming another attempt' do
    call_record = call_for(caller_number: candidate.mobile_number)
    described_class.call(candidate_ai_call: call_record, params: { 'reference_number' => assignment.reference_number })
    attempts_before = call_record.reload.verification_attempts

    result = described_class.call(candidate_ai_call: call_record, params: { 'reference_number' => 'anything' })

    expect(result.verified).to be(true)
    expect(call_record.reload.verification_attempts).to eq(attempts_before)
  end

  it 'short-circuits to locked once already failed, without consuming another attempt' do
    call_record = call_for(caller_number: '+929999999999')
    described_class::MAX_ATTEMPTS.times do
      described_class.call(candidate_ai_call: call_record, params: { 'reference_number' => 'BOGUS-1' })
    end
    described_class.call(candidate_ai_call: call_record, params: { 'reference_number' => 'BOGUS-1' })
    attempts_before = call_record.reload.verification_attempts

    result = described_class.call(candidate_ai_call: call_record, params: { 'reference_number' => 'anything' })

    expect(result.locked).to be(true)
    expect(call_record.reload.verification_attempts).to eq(attempts_before)
  end
end
