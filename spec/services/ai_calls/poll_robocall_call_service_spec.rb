# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::PollRobocallCallService do
  let(:adapter) { instance_double(AiCalls::Providers::RobocallAdapter) }
  let(:configuration) { instance_double(AiCalls::RobocallConfiguration, retry_window_minutes: 30) }
  let(:call_record) do
    create(:candidate_ai_call, provider_code: 'robocall', robocall_call_id: '20076', status: 'queued',
                               call_reason: 'workflow_stage_notification', workflow_stage_code: 'verified',
                               created_at: 2.minutes.ago)
  end

  def status(code, dtmf = nil) = AiCalls::Providers::RobocallAdapter::CallStatus.new(status_code: code, dtmf:)

  def poll(call = call_record) = described_class.new(candidate_ai_call: call, adapter:, configuration:).call

  def stub_status(code, dtmf = nil) = allow(adapter).to receive(:fetch_call).and_return(status(code, dtmf))

  it 'does nothing for a call that is already finished or has no provider call id' do
    allow(adapter).to receive(:fetch_call)

    poll(create(:candidate_ai_call, provider_code: 'robocall', robocall_call_id: '1', status: 'completed'))
    poll(create(:candidate_ai_call, provider_code: 'robocall', robocall_call_id: nil))

    expect(adapter).not_to have_received(:fetch_call)
  end

  it 'leaves a call that is still initiated or pushed to SIP queued' do
    [1, 8].each do |code|
      stub_status(code)
      expect(poll.status).to eq('queued')
    end
    expect(call_record.candidate_ai_call_events).to be_empty
  end

  describe 'an answered call' do
    it 'moves to in_progress the first time it is seen answered, and does not repeat the event' do
      stub_status(2)

      expect(poll.status).to eq('in_progress')
      expect(call_record.reload.answered_at).to be_present
      expect { poll }.not_to(change { call_record.candidate_ai_call_events.count })
    end

    it 'completes as answered/resolved as soon as a key is pressed, storing the key' do
      stub_status(2, '1')

      result = poll

      expect(result).to have_attributes(status: 'completed', outcome: 'answered', outcome_reason: 'resolved',
                                        extracted_data: { 'dtmf' => '1' }, callback_requested_at: nil)
      expect(result.candidate_ai_call_events.pluck(:event_key)).to eq(["robocall:#{call_record.id}:completed"])
      expect(result.communication.reload.status_code).to eq('completed')
    end

    it 'maps key 3 to callback_required and records when it was requested' do
      stub_status(2, '3')

      expect(poll).to have_attributes(outcome: 'callback_required', outcome_reason: 'candidate_requested',
                                      callback_requested_at: be_present)
    end

    it 'keeps waiting for a key press, then completes without one after the wait' do
      call_record.update!(status: 'in_progress', answered_at: 1.minute.ago)
      stub_status(2)
      expect(poll.status).to eq('in_progress')

      call_record.update!(answered_at: described_class::DTMF_WAIT.ago - 1.second)
      expect(poll).to have_attributes(status: 'completed', outcome: 'answered', outcome_reason: 'resolved',
                                      extracted_data: {})
    end
  end

  describe 'a call that was not answered' do
    {
      3 => 'provider_failure', 4 => 'busy', 5 => 'no_answer', 6 => 'hangup'
    }.each do |code, reason|
      it "closes status #{code} as not_answered/#{reason} once RoboCall's retry window has passed" do
        call_record.update!(created_at: 31.minutes.ago)
        stub_status(code)

        expect(poll).to have_attributes(status: 'failed', outcome: 'not_answered', outcome_reason: reason,
                                        completed_at: be_present)
      end
    end

    it 'stays open while RoboCall may still retry, without recording anything' do
      call_record.update!(created_at: 10.minutes.ago)
      stub_status(5)

      expect(poll).to have_attributes(status: 'queued', outcome: nil)
      expect(call_record.candidate_ai_call_events).to be_empty
    end

    it 'picks up a retry that is answered after an earlier unanswered attempt' do
      call_record.update!(created_at: 10.minutes.ago)
      stub_status(5)
      poll
      stub_status(2, '1')

      expect(poll).to have_attributes(status: 'completed', outcome: 'answered', extracted_data: { 'dtmf' => '1' })
    end

    it 'closes a call as answered when it was seen answered and then reads as not answered (the candidate hung up)' do
      call_record.update!(status: 'in_progress', answered_at: 1.minute.ago)
      stub_status(6)

      expect(poll).to have_attributes(status: 'completed', outcome: 'answered', outcome_reason: 'resolved')
    end
  end

  describe 'a call that never produces a result' do
    it 'is left alone while young, even if the provider cannot be read or reports nothing usable' do
      allow(adapter).to receive(:fetch_call).and_raise(AiCallProviderRequestError)
      expect(poll.status).to eq('queued')

      stub_status(nil)
      expect(poll.status).to eq('queued')
    end

    it 'goes to manual review once it has been open past the retry window and its margin' do
      call_record.update!(created_at: 46.minutes.ago)
      allow(adapter).to receive(:fetch_call).and_raise(AiCallProviderUnavailableError)

      expect(poll).to have_attributes(status: 'completed', outcome: nil, outcome_reason: 'needs_manual_review')
    end
  end
end
