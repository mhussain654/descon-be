# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::OutboundCallGuard do
  let(:configuration) do
    instance_double(
      AiCalls::Configuration,
      outbound_enabled?: true,
      calling_hours_start: 9,
      calling_hours_end: 19,
      admin_trigger_rate_limit_per_hour: 50,
      daily_outbound_call_limit: 200,
      outbound_trigger_cooldown_minutes: 60
    )
  end

  let(:guard) { described_class.new(configuration:) }

  describe '#ensure_allowed!' do
    it 'passes when outbound calling is enabled, within hours, and the admin is under their rate limit' do
      travel_to(Time.zone.parse('2026-09-10T12:00:00+05:00')) do
        expect { guard.ensure_allowed!(actor: create(:user)) }.not_to raise_error
      end
    end

    it 'raises when outbound calling is disabled' do
      allow(configuration).to receive(:outbound_enabled?).and_return(false)

      expect { guard.ensure_allowed!(actor: nil) }.to raise_error(AiCallOutboundDisabledError)
    end

    it 'raises outside allowed calling hours (Pakistan-local)' do
      travel_to(Time.zone.parse('2026-09-10T03:00:00+05:00')) do
        expect { guard.ensure_allowed!(actor: nil) }.to raise_error(AiCallOutsideCallingHoursError)
      end
    end

    it 'raises when the triggering admin has hit their hourly rate limit' do
      travel_to(Time.zone.parse('2026-09-10T12:00:00+05:00')) do
        allow(configuration).to receive(:admin_trigger_rate_limit_per_hour).and_return(1)
        actor = create(:user)
        create(:candidate_ai_call, triggered_by: actor)

        expect { guard.ensure_allowed!(actor:) }.to raise_error(AiCallAdminRateLimitedError)
      end
    end

    it 'does not rate-limit when no actor is given' do
      travel_to(Time.zone.parse('2026-09-10T12:00:00+05:00')) do
        allow(configuration).to receive(:admin_trigger_rate_limit_per_hour).and_return(0)

        expect { guard.ensure_allowed!(actor: nil) }.not_to raise_error
      end
    end
  end

  describe '#ensure_not_throttled!' do
    let(:assignment) { create(:candidate_assignment) }

    def call_for(assignment, call_reason: 'missing_documents')
      create(:candidate_ai_call, communication: create(:communication, candidate_assignment: assignment), call_reason:)
    end

    it 'passes when under the daily limit and outside the cooldown window' do
      expect do
        guard.ensure_not_throttled!(candidate_assignment: assignment, call_reason: 'missing_documents')
      end.not_to raise_error
    end

    it 'raises once the daily outbound call limit is reached' do
      allow(configuration).to receive(:daily_outbound_call_limit).and_return(1)
      create(:candidate_ai_call)

      expect do
        guard.ensure_not_throttled!(candidate_assignment: assignment, call_reason: 'missing_documents')
      end.to raise_error(AiCallDailyLimitReachedError)
    end

    it 'raises when the same candidate_assignment+call_reason was triggered within the cooldown window' do
      call_for(assignment, call_reason: 'missing_documents')

      expect do
        guard.ensure_not_throttled!(candidate_assignment: assignment, call_reason: 'missing_documents')
      end.to raise_error(AiCallTriggerCooldownError)
    end

    it 'does not raise for a different call_reason on the same assignment' do
      call_for(assignment, call_reason: 'missing_documents')

      expect do
        guard.ensure_not_throttled!(candidate_assignment: assignment, call_reason: 'flight_information')
      end.not_to raise_error
    end

    it 'does not raise once the cooldown window has elapsed' do
      travel_to(2.hours.ago) { call_for(assignment, call_reason: 'missing_documents') }

      expect do
        guard.ensure_not_throttled!(candidate_assignment: assignment, call_reason: 'missing_documents')
      end.not_to raise_error
    end
  end
end
