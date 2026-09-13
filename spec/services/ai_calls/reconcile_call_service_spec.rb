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

    it 'applies the outcome when ElevenLabs has a conversation record' do
      call_record = create(:candidate_ai_call, status: 'ringing', elevenlabs_conversation_id: 'conversation-1')
      allow(elevenlabs_adapter).to receive(:fetch_conversation).and_return(
        'data' => {
          'conversation_id' => 'conversation-1',
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
