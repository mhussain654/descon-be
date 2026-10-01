# frozen_string_literal: true

module Api
  module V1
    module AiCalls
      module Elevenlabs
        # Receives ElevenLabs' conversation-initiation webhook for an
        # inbound call and creates the matching CandidateAiCall. Response
        # is deliberately minimal and uniformly shaped whether or not the
        # caller matched a candidate -- this endpoint never signals
        # match/no-match. Unauthenticated by session; authenticity comes
        # from the ElevenLabs-Signature HMAC.
        class ConversationInitiationWebhooksController < ApplicationController
          # ElevenLabs requires this exact response contract for a
          # conversation-initiation webhook -- NOT this app's usual
          # {data, meta, errors} envelope (render_success). A malformed or
          # non-2xx response here doesn't just look wrong: per ElevenLabs'
          # docs, it prevents the call from connecting at all. `type` must
          # be exactly this literal string; `dynamic_variables` may be `{}`
          # since nothing here needs per-call prompt/variable overrides
          # today (unlike TriggerOutboundCallService's outbound flow, which
          # sets dynamic_variables directly on the initiate-call request,
          # not via this webhook).
          CLIENT_DATA_RESPONSE = { type: 'conversation_initiation_client_data', dynamic_variables: {} }.freeze

          def create
            ::AiCalls::HandleConversationInitiationService.call(
              header: request.headers['ElevenLabs-Signature'],
              raw_body: request.raw_post,
              params: params.except(:controller, :action).to_unsafe_h,
              request_id: request.request_id
            )

            set_standard_response_headers
            render json: CLIENT_DATA_RESPONSE
          end
        end
      end
    end
  end
end
