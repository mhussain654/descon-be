# frozen_string_literal: true

module AiCalls
  # Parses the ElevenLabs `post_call_transcription` webhook payload into the
  # fields this app needs.
  #
  # ASSUMED SHAPE -- based on ElevenLabs' documented Conversational AI
  # webhook/data-collection format (data.conversation_id,
  # data.analysis.data_collection_results for our structured extraction).
  # Not yet verified against a real delivered payload (no sandbox/production
  # ElevenLabs credentials exist yet -- see the plan's "External inputs
  # required from the client"). Confirm and adjust this class -- and only
  # this class, the rest of the pipeline doesn't care about the raw shape --
  # once real payloads are available.
  class PostCallWebhookPayload
    def initialize(raw)
      @raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    end

    def conversation_id
      data['conversation_id']
    end

    # ElevenLabs' documented conversation lifecycle status: 'initiated',
    # 'in-progress', 'processing', 'done', or 'failed'. Only present on the
    # GET /v1/convai/conversations/:id response the reconciliation job reads
    # (AiCalls::ReconcileCallService) -- the post_call_transcription webhook
    # payload doesn't carry it (a webhook only fires once the conversation
    # is already done), so this is nil on that path.
    def status
      data['status']
    end

    def call_duration_seconds
      data.dig('metadata', 'call_duration_secs')
    end

    # Confirmed directly with ElevenLabs support (2026-09-15): this field is
    # an empty string specifically when the agent exits via a
    # transfer_to_number conference transfer, as opposed to a normal user-
    # or agent-initiated end (which carry a real reason string). Checked
    # for exact equality with '', not blank? -- a missing/nil value (e.g.
    # an older payload shape, or a call that never used this field) is a
    # distinct, unknown case that must fall through to the normal
    # extraction-based outcome mapping, not be read as a transfer.
    def end_reason
      data['end_reason']
    end

    def recording_reference
      data.dig('metadata', 'phone_call', 'recording_url') || data.dig('metadata', 'recording_url')
    end

    # The structured post-call extraction ElevenLabs' data-collection
    # feature produces (see AiCalls::OutcomeMapper for the fields read from
    # this): {human_answered, callback_requested, escalation_requested,
    # call_resolved, ...}.
    def extraction
      data.dig('analysis', 'data_collection_results')
    end

    # ElevenLabs' documented call-summary text (ASSUMED SHAPE, see the class
    # comment above -- 'transcript_summary' per their documented analysis
    # object).
    def summary
      data.dig('analysis', 'transcript_summary').presence
    end

    def transcript_text
      turns = data['transcript']
      return nil unless turns.is_a?(Array)

      joined = turns.filter_map { |turn| turn['message'] || turn['text'] }.join("\n").presence
      TranscriptRedactor.call(joined)
    end

    private

    def data
      @raw['data'].is_a?(Hash) ? @raw['data'] : @raw
    end
  end
end
