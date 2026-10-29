# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateSms::StageMessage do
  before { ensure_canonical_workflow_stages! }

  let(:candidate) { create(:candidate, full_name: 'Daim Javed') }
  let(:assignment) { create(:candidate_assignment, candidate:, onboarding_fee_amount: 1500) }

  # A visa decision or flight detail brings its own stage history entry.
  def enter(stage_code, evidence: {}, action_type: nil, history_entry: nil)
    stage = WorkflowStage.find_by!(code: stage_code)
    history_entry ||= create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: stage)
    process_stage = action_type && instance_double(MobilizationProcessStage, action_type:)
    described_class.call(
      history_entry:, evidence:,
      context: { candidate:, assignment:, destination_stage: stage, destination_process_stage: process_stage }
    )
    history_entry
  end

  def delivery = CandidateSmsDelivery.sole

  it 'welcomes a newly registered candidate when their documents are first asked for' do
    history_entry = enter('documents_pending')

    expect(delivery).to have_attributes(message_code: 'registered', dedupe_key: "registered:#{history_entry.id}",
                                        variables: { 'name' => 'Daim Javed' })
  end

  it 'tells the candidate their medical date' do
    enter('medical_appointment', evidence: { 'medical_appointment_date' => '2026-11-04' },
                                 action_type: 'medical_appointment')

    expect(delivery).to have_attributes(message_code: 'medical_appointment',
                                        variables: include('date' => '04-11-2026'))
  end

  it 'sends no medical SMS when no appointment date was given' do
    enter('medical_appointment', action_type: 'medical_appointment')

    expect(CandidateSmsDelivery.count).to eq(0)
  end

  it 'tells an unfit candidate to contact Descon' do
    enter('medical_fit', evidence: { 'medical_outcome_code' => 'unfit' }, action_type: 'medical_outcome')

    expect(delivery.message_code).to eq('medical_unfit')
  end

  it 'sends a fit candidate nothing yet: the fee SMS follows' do
    enter('medical_fit', evidence: { 'medical_outcome_code' => 'fit' }, action_type: 'medical_outcome')

    expect(CandidateSmsDelivery.count).to eq(0)
  end

  it 'asks for the fee with its amount in whole rupees' do
    enter('fee_pending')

    expect(delivery).to have_attributes(message_code: 'fee_pending', variables: include('amount' => '1500'))
  end

  it 'tells the candidate their QVC date, once per attempt' do
    attempt = create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: Date.new(2026, 11, 9))

    enter('qvc_appointment_booked')

    expect(delivery).to have_attributes(message_code: 'qvc_appointment', dedupe_key: "qvc_appointment:#{attempt.id}",
                                        variables: include('date' => '09-11-2026'))
  end

  it 'tells the candidate whether the visa was issued or rejected' do
    decision = create(:candidate_visa_decision, candidate_assignment: assignment, outcome_code: 'rejected',
                                                rejection_reason_code: 'other')

    enter('visa_issued_or_rejected', history_entry: decision.candidate_stage_history)

    expect(delivery).to have_attributes(message_code: 'visa_rejected', dedupe_key: "visa_decision:#{decision.id}")
  end

  it 'gives the date of a protection call still to happen' do
    enter('protection_call',
          evidence: { 'protection_call_status' => 'scheduled', 'protection_call_on' => '2026-11-10' })

    expect(delivery).to have_attributes(message_code: 'protection_call', variables: include('date' => '10-11-2026'))
  end

  it 'sends nothing for a protection call already done' do
    enter('protection_call',
          evidence: { 'protection_call_status' => 'completed', 'protection_call_on' => '2026-11-10' })

    expect(CandidateSmsDelivery.count).to eq(0)
  end

  it 'confirms the ticket handover date' do
    enter('ticket_handover', evidence: { 'ticket_handed_over_on' => '2026-11-12' })

    expect(delivery).to have_attributes(message_code: 'ticket_handover', variables: include('date' => '12-11-2026'))
  end

  it 'gives the flight with its departure in Pakistan time' do
    detail = create(:candidate_flight_detail, candidate_assignment: assignment, airline: 'Qatar Airways',
                                              flight_number: 'QR-629', sector: 'LHE-DOH',
                                              flight_departure_at: Time.utc(2026, 11, 20, 21, 15))

    enter('flight_details_uploaded', history_entry: detail.candidate_stage_history)

    expect(delivery).to have_attributes(
      message_code: 'flight_details',
      variables: include('airline' => 'Qatar Airways', 'flight' => 'QR-629', 'sector' => 'LHE-DOH',
                         'date' => '21-11-2026', 'time' => '02:15')
    )
  end

  it 'sends nothing for a stage that is internal to Descon' do
    enter('under_verification')

    expect(CandidateSmsDelivery.count).to eq(0)
  end
end
