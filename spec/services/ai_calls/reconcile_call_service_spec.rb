# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::ReconcileCallService do
  let(:twilio_adapter) { instance_double(AiCalls::Providers::TwilioAdapter) }
  let(:elevenlabs_adapter) { instance_double(AiCalls::Providers::ElevenlabsAdapter) }

  def service_for(call_record)
    described_class.new(candidate_ai_call: call_record, twilio_adapter:, elevenlabs_adapter:)
  end

  describe '.due?' do
    it 'is true once a fixed-threshold status has aged past its window' do
      call_record = build_stubbed(:candidate_ai_call, status: 'ringing', updated_at: 3.minutes.ago)

      expect(described_class.due?(call_record)).to be(true)
    end

    it 'is false before the threshold elapses' do
      call_record = build_stubbed(:candidate_ai_call, status: 'ringing', updated_at: 10.seconds.ago)

      expect(described_class.due?(call_record)).to be(false)
    end

    it 'uses the configured max call duration (plus buffer) for in_progress' do
      configuration = instance_double(AiCalls::Configuration, max_call_duration_minutes: 10)
      call_record = build_stubbed(:candidate_ai_call, status: 'in_progress', updated_at: 14.minutes.ago)

      expect(described_class.due?(call_record, configuration:)).to be(false)

      call_record_stuck = build_stubbed(:candidate_ai_call, status: 'in_progress', updated_at: 16.minutes.ago)
      expect(described_class.due?(call_record_stuck, configuration:)).to be(true)
    end

    it 'is false for a status with no reconciliation threshold' do
      call_record = build_stubbed(:candidate_ai_call, status: 'completed', updated_at: 1.hour.ago)

      expect(described_class.due?(call_record)).to be(false)
    end
  end

  describe '#call' do
    it 'is a no-op for an already-terminal call' do
      call_record = create(:candidate_ai_call, status: 'completed')

      expect(service_for(call_record).call).to eq(call_record)
      expect(call_record.candidate_ai_call_events.count).to eq(0)
    end

    it 'applies the outcome when ElevenLabs reports the conversation is done' do
      call_record = create(:candidate_ai_call, status: 'ringing', elevenlabs_conversation_id: 'conversation-1')
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => {
          'conversation_id' => 'conversation-1', 'status' => 'done',
          'analysis' => { 'data_collection_results' => { 'human_answered' => true, 'call_resolved' => true } },
          'transcript' => [{ 'role' => 'agent', 'message' => 'Hello.' }]
        }
      )

      result = service_for(call_record).call

      expect(result.status).to eq('completed')
      expect(result.outcome).to eq('answered')
      expect(result.outcome_reason).to eq('resolved')
      expect(result.candidate_ai_call_transcript.transcript).to eq('Hello.')
    end

    it "maps a conference-transfer exit (end_reason: '') recovered through reconciliation" do
      call_record = create(:candidate_ai_call, status: 'ringing', elevenlabs_conversation_id: 'conversation-1')
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => { 'conversation_id' => 'conversation-1', 'status' => 'done', 'end_reason' => '' }
      )

      result = service_for(call_record).call

      expect(result.outcome).to eq('answered')
      expect(result.outcome_reason).to eq('transferred_to_human')
    end

    it 'stamps an expiry on a transcript recovered through reconciliation' do
      call_record = create(:candidate_ai_call, status: 'ringing', elevenlabs_conversation_id: 'conversation-1')
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => {
          'conversation_id' => 'conversation-1', 'status' => 'done',
          'analysis' => { 'data_collection_results' => { 'human_answered' => true, 'call_resolved' => true } },
          'transcript' => [{ 'role' => 'agent', 'message' => 'Hello.' }]
        }
      )

      freeze_time do
        result = service_for(call_record).call

        expect(result.candidate_ai_call_transcript.expires_at).to eq(90.days.from_now)
      end
    end

    it 'does not complete the call while ElevenLabs reports it queued or in progress' do
      %w[initiated in-progress processing].each do |elevenlabs_status|
        call_record = create(:candidate_ai_call, status: 'ringing',
                                                 elevenlabs_conversation_id: "conversation-#{elevenlabs_status}")
        allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
          'data' => { 'conversation_id' => "conversation-#{elevenlabs_status}", 'status' => elevenlabs_status }
        )

        result = service_for(call_record).call

        expect(result.status).not_to be_in(%w[completed failed cancelled])
      end
    end

    it "synchronizes local status forward to match ElevenLabs' in-progress conversation state" do
      call_record = create(:candidate_ai_call, status: 'ringing', elevenlabs_conversation_id: 'conversation-1')
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => { 'conversation_id' => 'conversation-1', 'status' => 'in-progress' }
      )

      result = service_for(call_record).call

      expect(result.status).to eq('in_progress')
      expect(result.candidate_ai_call_events.count).to eq(1)
    end

    it 'never regresses local status when ElevenLabs reports an earlier-looking open status' do
      call_record = create(:candidate_ai_call, status: 'processing', elevenlabs_conversation_id: 'conversation-1')
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => { 'conversation_id' => 'conversation-1', 'status' => 'initiated' }
      )

      result = service_for(call_record).call

      expect(result.status).to eq('processing')
      expect(result.candidate_ai_call_events.count).to eq(0)
    end

    it 'reconciles against Twilio when ElevenLabs reports the conversation failed' do
      call_record = create(:candidate_ai_call, status: 'in_progress', elevenlabs_conversation_id: 'conversation-1',
                                               twilio_call_sid: 'CA-1')
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => { 'conversation_id' => 'conversation-1', 'status' => 'failed' }
      )
      allow(twilio_adapter).to receive(:fetch_call).and_return('status' => 'no-answer')

      result = service_for(call_record).call

      expect(result.status).to eq('failed')
      expect(result.outcome).to eq('not_answered')
      expect(result.outcome_reason).to eq('no_answer')
    end

    it 'retries (no-op) on a missing/unrecognized ElevenLabs status before the review bound elapses' do
      call_record = create(:candidate_ai_call, status: 'in_progress', elevenlabs_conversation_id: 'conversation-1',
                                               updated_at: 5.minutes.ago)
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => { 'conversation_id' => 'conversation-1', 'status' => 'something_new' }
      )

      result = service_for(call_record).call

      expect(result.status).to eq('in_progress')
      expect(result.candidate_ai_call_events.count).to eq(0)
    end

    it 'routes a missing/unrecognized ElevenLabs status to manual review once stuck past the bound' do
      call_record = create(:candidate_ai_call, status: 'in_progress', elevenlabs_conversation_id: 'conversation-1',
                                               updated_at: 31.minutes.ago)
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => { 'conversation_id' => 'conversation-1' }
      )

      result = service_for(call_record).call

      expect(result.status).to eq('completed')
      expect(result.outcome).to be_nil
      expect(result.outcome_reason).to eq('needs_manual_review')
    end

    # Regression: a transient ElevenLabs failure (rate limit, timeout, 5xx)
    # fetching a conversation that *is* expected to exist must not be
    # treated the same as "no conversation exists" -- previously this fell
    # straight through to close_from_twilio_status!, which immediately
    # closed the call as needs_manual_review the moment Twilio reported
    # 'completed', permanently losing the chance to ever fetch the
    # transcript/analysis (reconciliation never revisits a terminal call).
    it 'retries (no-op) on a transient ElevenLabs fetch failure, even if Twilio already reports the call completed' do
      call_record = create(:candidate_ai_call, status: 'processing', elevenlabs_conversation_id: 'conversation-1',
                                               twilio_call_sid: 'CA-1', updated_at: 5.minutes.ago)
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_raise(AiCallProviderRequestError)
      allow(twilio_adapter).to receive(:fetch_call).and_return('status' => 'completed')

      result = service_for(call_record).call

      expect(result.status).to eq('processing')
      expect(result.candidate_ai_call_events.count).to eq(0)
      expect(twilio_adapter).not_to have_received(:fetch_call)
    end

    it 'routes a persistent ElevenLabs fetch failure to manual review, with a failure_message, past the review bound' do
      call_record = create(:candidate_ai_call, status: 'processing', elevenlabs_conversation_id: 'conversation-1',
                                               updated_at: 31.minutes.ago)
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_raise(AiCallProviderRequestError)

      result = service_for(call_record).call

      expect(result.status).to eq('completed')
      expect(result.outcome).to be_nil
      expect(result.outcome_reason).to eq('needs_manual_review')
      expect(result.failure_message).to be_present
    end

    it 'persists summary, extracted_data and provider_status when ElevenLabs reports the conversation is done' do
      call_record = create(:candidate_ai_call, status: 'ringing', elevenlabs_conversation_id: 'conversation-1')
      extraction = { 'human_answered' => true, 'call_resolved' => true }
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => {
          'conversation_id' => 'conversation-1', 'status' => 'done',
          'analysis' => { 'data_collection_results' => extraction,
                          'transcript_summary' => 'Candidate confirmed receipt.' }
        }
      )

      result = service_for(call_record).call

      expect(result.summary).to eq('Candidate confirmed receipt.')
      expect(result.extracted_data).to eq(extraction)
      expect(result.provider_status).to eq('done')
    end

    it "syncs the call's Communication envelope when reconciliation closes it out" do
      call_record = create(:candidate_ai_call, status: 'ringing', elevenlabs_conversation_id: 'conversation-1')
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => {
          'conversation_id' => 'conversation-1', 'status' => 'done',
          'analysis' => { 'data_collection_results' => { 'human_answered' => true, 'call_resolved' => true } }
        }
      )

      result = service_for(call_record).call

      expect(result.communication.reload.status_code).to eq('completed')
    end

    it 'closes as not_answered when ElevenLabs has no record and Twilio reports busy' do
      call_record = create(:candidate_ai_call, status: 'ringing', twilio_call_sid: 'CA-1')
      allow(twilio_adapter).to receive(:fetch_call).and_return('status' => 'busy')

      result = service_for(call_record).call

      expect(result.status).to eq('failed')
      expect(result.outcome).to eq('not_answered')
      expect(result.outcome_reason).to eq('busy')
    end

    it 'routes to needs_manual_review when Twilio reports completed but ElevenLabs has no record' do
      call_record = create(:candidate_ai_call, status: 'processing', twilio_call_sid: 'CA-1')
      allow(twilio_adapter).to receive(:fetch_call).and_return('status' => 'completed')

      result = service_for(call_record).call

      expect(result.status).to eq('completed')
      expect(result.outcome).to be_nil
      expect(result.outcome_reason).to eq('needs_manual_review')
    end

    it 'is a no-op when neither provider has useful signal yet' do
      call_record = create(:candidate_ai_call, status: 'ringing', twilio_call_sid: 'CA-1')
      allow(twilio_adapter).to receive(:fetch_call).and_return('status' => 'ringing')

      result = service_for(call_record).call

      expect(result.status).to eq('ringing')
      expect(call_record.candidate_ai_call_events.count).to eq(0)
    end

    it 'treats a provider error as no signal rather than raising' do
      call_record = create(:candidate_ai_call, status: 'ringing', twilio_call_sid: 'CA-1')
      allow(twilio_adapter).to receive(:fetch_call).and_raise(AiCallProviderRequestError)

      expect { service_for(call_record).call }.not_to raise_error
      expect(call_record.reload.status).to eq('ringing')
    end

    it 'is idempotent when run twice for the same observed status' do
      call_record = create(:candidate_ai_call, status: 'ringing', twilio_call_sid: 'CA-1')
      allow(twilio_adapter).to receive(:fetch_call).and_return('status' => 'busy')

      service_for(call_record).call
      service_for(call_record).call

      expect(call_record.candidate_ai_call_events.count).to eq(1)
    end
  end
end
