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
          def create
            ::AiCalls::HandleConversationInitiationService.call(
              header: request.headers['ElevenLabs-Signature'],
              raw_body: request.raw_post,
              params: params.except(:controller, :action).to_unsafe_h,
              request_id: request.request_id
            )

            render_success(data: {})
          end
        end
      end
    end
  end
end
