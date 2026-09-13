# frozen_string_literal: true

module AiCalls
  # Places one outbound AI voice call per `plan` (AiCalls::OutboundCallPlan)
  # -- shared by the admin-triggered flow (4 fixed scenarios, `actor` set)
  # and the workflow-stage-triggered flow (`actor` nil). Mirrors Payments::
  # CheckoutSessionService's shape: lock the candidate/assignment, enforce
  # eligibility/safety checks (AiCalls::OutboundCallGuard), then create the
  # local records and call the provider inside the same transaction -- if
  # the provider call raises, everything rolls back cleanly (no orphaned
  # "failed" row), matching how a failed KuickPay checkout-session creation
  # is handled.
  class TriggerOutboundCallService < ApplicationService
    LOCK_SCOPE = 'ai_calls:trigger_outbound'

    def initialize(candidate:, plan:, request_id:, actor: nil, configuration: AiCalls::Configuration.new)
      @candidate = candidate
      @plan = plan
      @actor = actor
      @request_id = request_id
      @configuration = configuration
      @guard = OutboundCallGuard.new(configuration:)
      @adapter = Providers::ElevenlabsAdapter.new(configuration:)
    end

    def call
      @guard.ensure_allowed!(actor: @actor)

      CandidateAssignment.transaction { execute_trigger }
    end

    private

    def execute_trigger
      lock_trigger!
      candidate, assignment = locked_candidate_and_assignment
      @guard.ensure_daily_limit_not_reached!
      # Only the admin-triggered (attributed) flow uses the per-reason
      # cooldown -- the workflow-stage-triggered flow (@actor nil) already
      # enforces its own, stronger, permanent per-stage dedup at the caller
      # (see AiCalls::OutboundCallGuard#ensure_cooldown_elapsed!).
      @guard.ensure_cooldown_elapsed!(candidate_assignment: assignment, call_reason: @plan.call_reason) if @actor

      call_record = create_call_record!(candidate:, assignment:)
      initiate_provider_call!(call_record)
      call_record.reload
    end

    # Serializes concurrent triggers for the same candidate+reason so two
    # near-simultaneous requests can't both pass the cooldown check below
    # before either has committed -- the second waits for the first to
    # finish, then sees its just-created row and is correctly rejected.
    def lock_trigger!
      Database::AdvisoryTransactionLock.call(scope: LOCK_SCOPE, key: "#{@candidate.id}:#{@plan.call_reason}")
    end

    def locked_candidate_and_assignment
      candidate = Candidate.lock.find(@candidate.id)
      raise InactiveAccountError unless candidate.active?

      assignment = candidate.current_assignment
      raise NoCurrentAssignmentError if assignment.blank?

      assignment.lock!
      [candidate, assignment]
    end

    def create_call_record!(candidate:, assignment:)
      communication = create_communication!(candidate:, assignment:)
      communication.create_candidate_ai_call!(call_attributes(candidate:, assignment:))
    end

    def create_communication!(candidate:, assignment:)
      Communication.create!(
        channel_code: 'ai_voice_call',
        direction_code: 'outbound',
        status_code: 'requested',
        candidate_assignment: assignment,
        initiated_by: @actor,
        locale: candidate.preferred_locale,
        recipient_masked: PhoneNumbers::Masker.call(candidate.mobile_number)
      )
    end

    def call_attributes(candidate:, assignment:)
      identity_attributes(candidate:, assignment:).merge(provider_attributes(candidate:))
    end

    def identity_attributes(candidate:, assignment:)
      {
        candidate:, candidate_assignment: assignment, triggered_by: @actor,
        direction: 'outbound', call_reason: @plan.call_reason, workflow_stage_code: @plan.workflow_stage_code,
        language_code: candidate.preferred_locale, status: 'requested', verification_status: 'not_applicable'
      }
    end

    def provider_attributes(candidate:)
      {
        provider_code: 'elevenlabs',
        elevenlabs_agent_id: @configuration.elevenlabs_outbound_agent_id,
        elevenlabs_agent_phone_number_id: @configuration.elevenlabs_agent_phone_number_id,
        prompt_template_code: @plan.call_reason,
        prompt_template_version: '1',
        agent_config_digest: AgentConfigs::Baseline.for(:outbound).digest,
        caller_number_masked: PhoneNumbers::Masker.call(candidate.mobile_number)
      }
    end

    def initiate_provider_call!(call_record)
      prompt = @plan.prompt_source.build(candidate: call_record.candidate, language_code: call_record.language_code)
      result = @adapter.initiate_outbound_call(outbound_call_request(call_record:, prompt:))

      call_record.update!(elevenlabs_conversation_id: result.conversation_id, twilio_call_sid: result.twilio_call_sid,
                          status: 'queued')
      record_trigger_event!(call_record)
    end

    def outbound_call_request(call_record:, prompt:)
      Providers::OutboundCallRequest.new(
        agent_id: call_record.elevenlabs_agent_id,
        agent_phone_number_id: call_record.elevenlabs_agent_phone_number_id,
        to_number: call_record.candidate.mobile_number,
        dynamic_variables: prompt.dynamic_variables,
        conversation_config_override: prompt.conversation_config_override,
        recording_enabled: @configuration.recording_enabled?
      )
    end

    def record_trigger_event!(call_record)
      event_source = @actor.present? ? 'admin_trigger' : 'workflow_stage_trigger'
      call_record.candidate_ai_call_events.create!(
        actor: @actor, provider_code: 'elevenlabs', event_source:, event_type: 'call_initiated',
        event_key: "#{event_source}:#{call_record.id}", occurred_at: Time.current, request_id: @request_id,
        payload: { call_reason: @plan.call_reason, conversation_id: call_record.elevenlabs_conversation_id }.compact
      )
    end
  end
end
