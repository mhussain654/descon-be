# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::RecordPostCallWebhookService do
  let(:candidate_ai_call) { create(:candidate_ai_call, status: 'queued', elevenlabs_conversation_id: 'conversation-1') }
  let(:adapter) { instance_double(AiCalls::Providers::ElevenlabsAdapter) }

  let(:raw_payload) do
    {
      'data' => {
        'conversation_id' => 'conversation-1',
        'metadata' => { 'call_duration_secs' => 42 },
        'analysis' => {
          'data_collection_results' => {
            'human_answered' => true, 'call_resolved' => true, 'callback_requested' => false,
            'escalation_requested' => false
          }
        },
        'transcript' => [{ 'role' => 'agent', 'message' => 'Hello.' }]
      }
    }
  end

  def service(params: raw_payload)
    described_class.new(header: 't=1,v0=abc', raw_body: params.to_json, params:, request_id: 'req-1', adapter:)
  end

  before do
    candidate_ai_call
    allow(adapter).to receive(:verify_webhook_signature!)
  end

  it 'verifies the signature before doing anything else' do
    service.call

    expect(adapter).to have_received(:verify_webhook_signature!).with(header: 't=1,v0=abc',
                                                                      raw_body: raw_payload.to_json)
  end

  it 'raises when the signature is invalid' do
    allow(adapter).to receive(:verify_webhook_signature!).and_raise(AiCallSignatureInvalidError)

    expect { service.call }.to raise_error(AiCallSignatureInvalidError)
  end

  it 'applies the resolved outcome, marks the call completed, and stores the transcript' do
    result = service.call

    expect(result.status).to eq('completed')
    expect(result.outcome).to eq('answered')
    expect(result.outcome_reason).to eq('resolved')
    expect(result.completed_at).to be_present
    expect(result.candidate_ai_call_transcript.transcript).to eq('Hello.')
  end

  it 'routes a malformed extraction to needs_manual_review' do
    malformed = raw_payload.deep_dup
    malformed['data']['analysis']['data_collection_results'] = nil

    result = service(params: malformed).call

    expect(result.outcome).to be_nil
    expect(result.outcome_reason).to eq('needs_manual_review')
  end

  it 'is idempotent -- a replayed delivery does not reapply or duplicate the transcript' do
    service.call
    candidate_ai_call.reload.update_columns(status: 'processing') # rubocop:disable Rails/SkipsModelValidations -- simulate a status change that a replay must not clobber

    result = service.call

    expect(result.status).to eq('processing')
    expect(CandidateAiCallEvent.where(candidate_ai_call:).count).to eq(1)
    expect(CandidateAiCallTranscript.where(candidate_ai_call:).count).to eq(1)
  end

  it 'raises when no call matches the conversation_id' do
    unknown = raw_payload.deep_dup
    unknown['data']['conversation_id'] = 'unknown-conversation'

    expect { service(params: unknown).call }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
