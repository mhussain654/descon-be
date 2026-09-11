# frozen_string_literal: true

module AiCalls
  # Handles ElevenLabs' conversation-initiation webhook for an inbound call:
  # creates one CandidateAiCall (+Communication) row idempotently, whether
  # or not the caller's number matches a known candidate -- the response is
  # uniformly shaped either way (see the plan's "Inbound voice identity
  # verification": never signal match/no-match directly). Actual identity
  # verification happens later, via the verify_caller_identity tool, not
  # here.
  class HandleConversationInitiationService < ApplicationService
    def initialize(header:, raw_body:, params:, request_id:, configuration: AiCalls::Configuration.new)
      @header = header
      @raw_body = raw_body
      @params = params
      @request_id = request_id
      @configuration = configuration
      @adapter = Providers::ElevenlabsAdapter.new(configuration:)
    end

    def call
      @adapter.verify_webhook_signature!(header: @header, raw_body: @raw_body)
      payload = ConversationInitiationPayload.new(@params)
      raise AiCallProviderRequestError if payload.conversation_id.blank?

      find_or_create_call!(payload)
    end

    private

    def find_or_create_call!(payload)
      existing = CandidateAiCall.find_by(elevenlabs_conversation_id: payload.conversation_id)
      return existing if existing.present?

      create_call!(payload)
    rescue ActiveRecord::RecordNotUnique
      CandidateAiCall.find_by!(elevenlabs_conversation_id: payload.conversation_id)
    end

    def create_call!(payload)
      caller_number = PhoneNumbers::Normalizer.call(payload.caller_number)
      candidate = matching_candidate(caller_number)
      assignment = candidate&.current_assignment

      ActiveRecord::Base.transaction do
        communication = create_communication!(candidate:, assignment:, caller_number:)
        communication.create_candidate_ai_call!(
          call_attributes(candidate:, assignment:, caller_number:, conversation_id: payload.conversation_id)
        )
      end
    end

    def matching_candidate(caller_number)
      return nil if caller_number.blank?

      Candidate.active.find_by(mobile_number: caller_number)
    end

    def create_communication!(candidate:, assignment:, caller_number:)
      Communication.create!(
        channel_code: 'ai_voice_call',
        direction_code: 'inbound',
        status_code: 'in_progress',
        candidate_assignment: assignment,
        locale: candidate&.preferred_locale || 'en',
        recipient_masked: PhoneNumbers::Masker.call(caller_number)
      )
    end

    def call_attributes(candidate:, assignment:, caller_number:, conversation_id:)
      identity_attributes(candidate:, assignment:).merge(
        provider_attributes(caller_number:, conversation_id:)
      )
    end

    def identity_attributes(candidate:, assignment:)
      {
        candidate:, candidate_assignment: assignment, direction: 'inbound', call_reason: 'general_helpline',
        language_code: candidate&.preferred_locale || 'en', status: 'in_progress', verification_status: 'pending',
        started_at: Time.current, answered_at: Time.current
      }
    end

    def provider_attributes(caller_number:, conversation_id:)
      {
        provider_code: 'elevenlabs', elevenlabs_agent_id: @configuration.elevenlabs_inbound_agent_id,
        elevenlabs_conversation_id: conversation_id, prompt_template_code: 'general_helpline',
        agent_config_digest: AgentConfigs::Baseline.for(:inbound).digest,
        caller_number: caller_number.presence, caller_number_masked: PhoneNumbers::Masker.call(caller_number)
      }
    end
  end
end
