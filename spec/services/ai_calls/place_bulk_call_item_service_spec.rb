# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::PlaceBulkCallItemService do
  let(:configuration) do
    instance_double(
      AiCalls::Configuration, robocall?: true, outbound_enabled?: true, calling_hours_start: 0, calling_hours_end: 24,
                              daily_outbound_call_limit: 200, admin_trigger_rate_limit_per_hour: 0,
                              outbound_trigger_cooldown_minutes: 60, recording_enabled?: false
    )
  end
  let(:voice) { create(:robocall_voice) }
  let(:item) { create_item }

  before { allow(AiCalls::Providers::RobocallAdapter).to receive(:new).and_return(robocall_adapter) }

  def robocall_adapter = @robocall_adapter ||= instance_double(AiCalls::Providers::RobocallAdapter)

  def batch = @batch ||= create(:bulk_call_batch, robocall_voice: voice, workflow_stage_code: 'verified')

  def candidate_and_assignment = @candidate_and_assignment ||= candidate_at('verified')

  def candidate = candidate_and_assignment.first

  def create_item
    create(:bulk_call_batch_item, bulk_call_batch: batch, candidate:,
                                  candidate_assignment: candidate_and_assignment.last)
  end

  def run = described_class.new(item_id: item.id, request_id: 'req-1', configuration:).call

  def accept_call(call_id = '555')
    allow(robocall_adapter).to receive(:initiate_call)
      .and_return(AiCalls::Providers::RobocallAdapter::CallResult.new(call_id:))
  end

  it 'places the call with the batch voice and records it on the item' do
    accept_call

    run

    expect(robocall_adapter).to have_received(:initiate_call).with(voice_id: voice.voice_id,
                                                                   to_number: candidate.mobile_number)
    call = item.reload.candidate_ai_call
    expect(item.status).to eq('placed')
    expect(call).to have_attributes(call_reason: 'bulk_voice_call', provider_voice_id: voice.voice_id,
                                    robocall_call_id: '555', triggered_by: batch.created_by, status: 'queued')
  end

  it 'is not blocked by the admin\'s hourly limit or by a recent call of the same kind (one admin action, one voice)' do
    accept_call
    call_with_voice(candidate_and_assignment.last, create(:robocall_voice), call_reason: 'bulk_voice_call')

    run

    expect(item.reload.status).to eq('placed')
  end

  it 'does nothing for an item that is no longer queued' do
    item.update!(status: 'placed')
    allow(robocall_adapter).to receive(:initiate_call)

    run

    expect(robocall_adapter).not_to have_received(:initiate_call)
  end

  describe 'skipped, so a later batch can pick the candidate again' do
    before { allow(robocall_adapter).to receive(:initiate_call) }

    def expect_no_call = expect(robocall_adapter).not_to have_received(:initiate_call)

    it 'skips a candidate who is no longer active' do
      candidate.update!(active: false)

      run

      expect(item.reload).to have_attributes(status: 'skipped', skip_reason: 'candidate_inactive')
      expect_no_call
    end

    it 'skips a candidate who has moved on from the batch stage' do
      candidate.update!(status_code: 'fee_paid')

      run

      expect(item.reload).to have_attributes(status: 'skipped', skip_reason: 'stage_changed')
      expect_no_call
    end

    {
      outside_calling_hours: { calling_hours_start: 0, calling_hours_end: 0 },
      daily_limit_reached: { daily_outbound_call_limit: 0 },
      calling_disabled: { outbound_enabled?: false }
    }.each do |reason, settings|
      it "skips with #{reason} when the safety controls refuse the call" do
        allow(configuration).to receive_messages(settings)

        run

        expect(item.reload).to have_attributes(status: 'skipped', skip_reason: reason.to_s)
        expect_no_call
      end
    end
  end

  describe 'a provider failure' do
    it 'marks the item failed, keeps no call record, and leaves the candidate eligible again' do
      allow(robocall_adapter).to receive(:initiate_call).and_raise(AiCallProviderRequestError)

      run

      expect(item.reload).to have_attributes(status: 'failed', skip_reason: 'provider_error', candidate_ai_call: nil)
      expect(CandidateAiCall.count).to eq(0)
      expect(Communication.count).to eq(0)
    end

    it 'also fails the item when RoboCall is not configured' do
      allow(robocall_adapter).to receive(:initiate_call).and_raise(AiCallProviderUnavailableError)

      run

      expect(item.reload).to have_attributes(status: 'failed', skip_reason: 'provider_error')
    end
  end
end
