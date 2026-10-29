# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::StartBulkCallBatchService do
  include ActiveJob::TestHelper

  let(:voice) { create(:robocall_voice, name_en: 'Visa approved') }
  let(:actor) { create(:user, role: 'admin') }
  let(:configuration) do
    instance_double(AiCalls::Configuration, robocall?: true, outbound_enabled?: true, calling_hours_start: 0,
                                            calling_hours_end: 24, daily_outbound_call_limit: 200)
  end

  def query_for(voice: self.voice, filter: { status: 'verified' })
    Admin::BulkCalls::EligibleCandidatesQuery.new(
      scope: Candidate.all, params: ActionController::Parameters.new(filter:), voice:
    )
  end

  def start(limit: 200, voice: self.voice, configuration: self.configuration)
    described_class.call(actor:, voice:, query: query_for(voice:), limit:, configuration:)
  end

  describe 'a successful start' do
    before { Array.new(3) { candidate_at('verified') } }

    it 'records the batch with a snapshot of the voice, and one queued item per candidate' do
      batch = start

      expect(batch).to have_attributes(
        created_by: actor, robocall_voice: voice, provider_voice_id: voice.voice_id, voice_name: 'Visa approved',
        workflow_stage_code: 'verified', requested_limit: 200, selected_count: 3
      )
      expect(batch.items.pluck(:status)).to eq(%w[queued queued queued])
      expect(batch.items.map(&:candidate_assignment_id)).to all(be_present)
    end

    it 'queues one job per candidate, spaced out so RoboCall is not hit all at once' do
      with_env('ROBOCALL_BULK_CALL_SPACING_SECONDS' => '10') do
        freeze_time do
          batch = start

          batch.items.order(:id).each_with_index do |item, index|
            due = Time.current + (index * 10).seconds
            expect(AiCalls::PlaceBulkCallItemJob).to have_been_enqueued.with(item.id).at(due)
          end
          expect(AiCalls::PlaceBulkCallItemJob).to have_been_enqueued.exactly(3).times
        end
      end
    end

    it 'records the narrowing filters used' do
      batch = described_class.call(
        actor:, voice:, limit: 200, configuration:,
        query: query_for(filter: { status: 'verified', country_code: 'qatar' })
      )

      expect(batch.filters).to eq('country_code' => 'qatar')
    end
  end

  describe 'batches that each take only their share' do
    it 'takes at most the limit, and the next batch takes only those not yet called' do
      Array.new(5) { candidate_at('verified') }

      first = start(limit: 2)
      second = start(limit: 2)
      third = start(limit: 2)

      expect([first, second, third].map(&:selected_count)).to eq([2, 2, 1])
      called = [first, second, third].flat_map { |batch| batch.items.pluck(:candidate_id) }
      expect(called.uniq.size).to eq(5)
      expect { start }.to raise_error(AiCallBulkNothingToCallError)
    end

    it 'does not pick again a candidate who already had a call with this voice' do
      _, assignment = candidate_at('verified')
      call_with_voice(assignment, voice)

      expect { start }.to raise_error(AiCallBulkNothingToCallError)
    end
  end

  describe 'refusals, before anything is recorded' do
    before { candidate_at('verified') }

    def expect_refused(error_class, message = nil, &)
      matcher = message ? raise_error(error_class, message) : raise_error(error_class)
      expect(&).to matcher
      expect(BulkCallBatch.count).to eq(0)
    end

    it 'refuses when RoboCall is not the voice provider' do
      allow(configuration).to receive(:robocall?).and_return(false)

      expect_refused(AiCallVoiceNotConfiguredError) { start }
    end

    it 'refuses while bulk calls are switched off in App Settings' do
      AppFeatureSetting.current.update!(bulk_calls_enabled: false)

      expect_refused(AiCallOutboundDisabledError) { start }
    end

    it 'refuses a call type that is switched off' do
      voice.update!(active: false)

      expect_refused(ValidationError) { start }
    end

    it 'refuses a limit below one or above the batch ceiling' do
      expect_refused(ValidationError) { start(limit: 0) }
      expect_refused(ValidationError, /at most 200/) { start(limit: 201) }
    end

    it 'honours a lower ceiling from the environment' do
      with_env('ROBOCALL_BULK_BATCH_LIMIT' => '1') do
        expect_refused(ValidationError, /at most 1/) { start(limit: 2) }
      end
    end

    it 'refuses while outbound calling is switched off' do
      allow(configuration).to receive(:outbound_enabled?).and_return(false)

      expect_refused(AiCallOutboundDisabledError) { start }
    end

    it 'refuses outside the allowed calling hours, rather than queueing calls for later' do
      allow(configuration).to receive_messages(calling_hours_start: 0, calling_hours_end: 0)

      expect_refused(AiCallOutsideCallingHoursError) { start }
    end

    it 'refuses a batch bigger than what is left of today\'s call budget' do
      candidate_at('verified')
      allow(configuration).to receive(:daily_outbound_call_limit).and_return(1)

      expect_refused(AiCallDailyLimitReachedError) { start }
    end
  end

  it 'refuses when nobody at the stage is left to call' do
    expect { start }.to raise_error(AiCallBulkNothingToCallError)
  end
end
