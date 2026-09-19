# frozen_string_literal: true

module AiCalls
  module Tools
    class GetPaymentStatus < VerifiedDataTool
      private

      def data
        eligibility = ::Payments::EligibilityService.call(candidate:)
        ::Payments::EligibilitySerializer.new(eligibility).as_json.merge(
          current_stage_name: stages_by_code(eligibility)[eligibility.current_stage_code]&.name_for,
          required_stage_name: stages_by_code(eligibility)[eligibility.required_stage_code]&.name_for,
          blocking_reason_descriptions: eligibility.blocking_reasons.map { |reason| blocking_reason_label(reason) }
        )
      end

      # `current_stage_code`/`required_stage_code`/`blocking_reasons` stay as
      # plain codes (this serializer is shared with other, code-consuming API
      # callers) -- the *_name/*_description fields below are what the agent
      # should actually say to the candidate.
      def stages_by_code(eligibility)
        @stages_by_code ||= ::WorkflowStage
                            .where(code: [eligibility.current_stage_code, eligibility.required_stage_code].compact)
                            .index_by(&:code)
      end

      def blocking_reason_label(reason)
        I18n.t("api.ai_calls.labels.payment_blocking_reasons.#{reason}", default: reason.to_s.humanize)
      end
    end
  end
end
