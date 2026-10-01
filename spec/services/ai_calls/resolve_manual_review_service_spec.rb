# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::ResolveManualReviewService do
  self.use_transactional_tests = false

  # None of this is rolled back with transactional tests off, so this file
  # is deliberately kept from ever creating a Candidate/CandidateAssignment
  # at all (candidate_assignment: nil below -- Communication#candidate_assignment
  # is optional, and a manual-review call not linked to any candidate is a
  # realistic scenario anyway) so there's no wide, FK-dependent table to
  # blanket-clean. The only rows left behind are Communication/CandidateAiCall/
  # CandidateAiCallEvent (this file's own subject) and the reviewer Users
  # each example creates, both cleaned up precisely below.
  let(:created_user_ids) { [] }

  around do |example|
    CandidateAiCallEvent.delete_all
    CandidateAiCall.delete_all
    Communication.delete_all
    example.run
  ensure
    CandidateAiCallEvent.delete_all
    CandidateAiCall.delete_all
    Communication.delete_all
    User.where(id: created_user_ids).delete_all
  end

  def reviewer
    user = create(:user, role: 'admin')
    created_user_ids << user.id
    user
  end

  def needs_review_call
    communication = create(:communication, channel_code: 'ai_voice_call', direction_code: 'inbound',
                                           candidate_assignment: nil, initiated_by: nil)
    communication.create_candidate_ai_call!(
      direction: 'inbound', call_reason: 'general_helpline', language_code: 'en', status: 'completed',
      verification_status: 'pending', outcome: nil, outcome_reason: 'needs_manual_review'
    )
  end

  it 'resolves the call, stamping the reviewer and an immutable audit event' do
    actor = reviewer
    call_record = needs_review_call

    result = described_class.call(
      candidate_ai_call: call_record, actor:, outcome: 'answered', outcome_reason: 'resolved',
      notes: 'Listened to the recording -- candidate confirmed receipt.', request_id: 'req-1'
    )

    expect(result.outcome).to eq('answered')
    expect(result.outcome_reason).to eq('resolved')
    expect(result.review_resolution).to eq('answered')
    expect(result.review_notes).to eq('Listened to the recording -- candidate confirmed receipt.')
    expect(result.reviewed_by).to eq(actor)
    expect(result.reviewed_at).to be_present

    event = call_record.candidate_ai_call_events.sole
    expect(event.event_type).to eq('manual_outcome_resolved')
    expect(event.event_source).to eq('admin_review')
    expect(event.actor).to eq(actor)
    expect(event.payload).to eq('selected_outcome' => 'answered',
                                'reason' => 'Listened to the recording -- candidate confirmed receipt.')
  end

  it 'keeps the original outcome_reason when none is given' do
    actor = reviewer
    call_record = needs_review_call

    result = described_class.call(candidate_ai_call: call_record, actor:, outcome: 'not_answered', request_id: 'req-1')

    expect(result.outcome_reason).to eq('needs_manual_review')
  end

  it 'raises when the call is not awaiting manual review' do
    actor = reviewer
    call_record = needs_review_call
    call_record.update!(outcome: 'answered', outcome_reason: 'resolved')

    expect do
      described_class.call(candidate_ai_call: call_record, actor:, outcome: 'not_answered', request_id: 'req-1')
    end.to raise_error(AiCallNotAwaitingReviewError)
  end

  it 'raises on a second resolution attempt, leaving the first resolution intact' do
    actor = reviewer
    call_record = needs_review_call
    described_class.call(candidate_ai_call: call_record, actor:, outcome: 'answered', request_id: 'req-1')

    expect do
      described_class.call(candidate_ai_call: call_record, actor:, outcome: 'not_answered', request_id: 'req-2')
    end.to raise_error(AiCallNotAwaitingReviewError)
    expect(call_record.reload.outcome).to eq('answered')
  end

  it 'allows only one concurrent resolution to succeed' do
    actor = reviewer
    call_record = needs_review_call
    outcomes = Queue.new

    worker = lambda do |outcome|
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.call(candidate_ai_call: call_record, actor:, outcome:, request_id: SecureRandom.uuid)
        outcomes << outcome
      rescue AiCallNotAwaitingReviewError
        outcomes << :not_awaiting_review
      end
    end

    threads = [
      Thread.new { worker.call('answered') },
      Thread.new { worker.call('not_answered') }
    ]
    threads.each(&:join)

    expect(Array.new(2) { outcomes.pop }).to include(:not_awaiting_review)
    expect(call_record.reload.outcome).to be_in(%w[answered not_answered])
    expect(call_record.candidate_ai_call_events.where(event_type: 'manual_outcome_resolved').count).to eq(1)
  end
end
