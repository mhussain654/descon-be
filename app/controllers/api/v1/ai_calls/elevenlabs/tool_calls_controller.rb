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
            ensure_call_accepts_tool_calls!
            handler = tool_handler

            outcome = ::AiCalls::ClaimToolCallEventService.call(
              candidate_ai_call:, tool_name: params[:tool_name], params: tool_params, request_id: request.request_id
            ) { |call_record| handler.call(candidate_ai_call: call_record, params: tool_params) }

            render_success(data: outcome.payload)
          end

          private

          def verify_tool_secret!
            configured = ::AiCalls::Configuration.new.tool_shared_secret.to_s
            provided = request.headers['X-AI-Calls-Tool-Secret'].to_s
            valid = configured.present? && provided.bytesize == configured.bytesize &&
                    ActiveSupport::SecurityUtils.secure_compare(provided, configured)
            raise AiCallToolSecretInvalidError unless valid
          end

          # A global shared secret plus a historical (ElevenLabs-controlled,
          # permanent) conversation_id must not grant indefinite access to
          # *current* candidate data -- reject once the call itself has
          # ended, and reject if the feature is currently disabled for that
          # call's direction (the initiation/trigger-time flag check alone
          # doesn't stop an already-in-flight call's tool calls once the
          # flag is flipped off mid-call).
          def ensure_call_accepts_tool_calls!
            raise AiCallToolCallNotAllowedError if candidate_ai_call.terminal_status?

            configuration = ::AiCalls::Configuration.new
            if candidate_ai_call.direction == 'inbound'
              raise AiCallInboundDisabledError unless configuration.inbound_enabled?
            elsif !configuration.outbound_enabled?
              raise AiCallOutboundDisabledError
            end
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
        end
      end
    end
  end
end
