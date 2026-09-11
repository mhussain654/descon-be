# frozen_string_literal: true

module Api
  module V1
    module AiCalls
      module Elevenlabs
        # Receives ElevenLabs' post-call webhook delivery and applies it to
        # the matching CandidateAiCall. Unauthenticated by session (no staff
        # user is involved) -- authenticity comes entirely from the
        # ElevenLabs-Signature HMAC, verified inside the service before
        # anything else happens.
        class PostCallWebhooksController < ApplicationController
          def create
            call_record = ::AiCalls::RecordPostCallWebhookService.call(
              header: request.headers['ElevenLabs-Signature'],
              raw_body: request.raw_post,
              params: params.except(:controller, :action).to_unsafe_h,
              request_id: request.request_id
            )

            render_success(data: { id: call_record.public_id, status: call_record.status })
          end
        end
      end
    end
  end
end
