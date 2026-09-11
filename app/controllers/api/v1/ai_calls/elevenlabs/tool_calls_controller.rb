# frozen_string_literal: true

module Api
  module V1
    module AiCalls
      module Elevenlabs
        # Single dispatcher for every ElevenLabs tool call (mirrors
        # Payments::ProviderRegistry's registry shape), one URL per
        # tool_name via the shared X-AI-Calls-Tool-Secret header rather than
        # a staff session. POST-only across every tool -- a GET here would
        # risk candidate-identifying data (verification answers) leaking
        # into query strings and access logs.
        class ToolCallsController < ApplicationController
          def create
            verify_tool_secret!
            handler = tool_handler
            result = handler.call(candidate_ai_call:, params: tool_params)
            record_event!(result)

            render_success(data: result)
          end

          private

          def verify_tool_secret!
            configured = ::AiCalls::Configuration.new.tool_shared_secret.to_s
            provided = request.headers['X-AI-Calls-Tool-Secret'].to_s
            valid = configured.present? && provided.bytesize == configured.bytesize &&
                    ActiveSupport::SecurityUtils.secure_compare(provided, configured)
            raise AiCallToolSecretInvalidError unless valid
          end

          def tool_handler
            ::AiCalls::Tools::Registry.fetch(params[:tool_name])
          rescue ArgumentError
            raise NotFoundError
          end

          def candidate_ai_call
            @candidate_ai_call ||= ::CandidateAiCall.find_by!(elevenlabs_conversation_id: conversation_id_param)
          end

          def conversation_id_param
            params.expect(:conversation_id)
          end

          def tool_params
            params.except(:controller, :action, :tool_name, :conversation_id).to_unsafe_h
          end

          def record_event!(result)
            candidate_ai_call.candidate_ai_call_events.create!(
              provider_code: 'elevenlabs', event_source: 'tool_call', event_type: params[:tool_name].to_s,
              event_key: "tool_call:#{candidate_ai_call.id}:#{params[:tool_name]}:#{SecureRandom.uuid}",
              occurred_at: Time.current, payload: result, request_id: request.request_id
            )
          end
        end
      end
    end
  end
end
