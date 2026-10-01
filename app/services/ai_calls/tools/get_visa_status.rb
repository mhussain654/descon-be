# frozen_string_literal: true

module AiCalls
  module Tools
    class GetVisaStatus < VerifiedDataTool
      private

      def data
        decision = assignment.candidate_visa_decisions.order(created_at: :desc).first
        return { status: 'pending', status_label: outcome_label('pending') } if decision.blank?

        {
          outcome_code: decision.outcome_code,
          outcome_label: outcome_label(decision.outcome_code),
          decision_date: decision.decision_date.iso8601,
          rejection_reason_code: decision.rejection_reason_code,
          rejection_reason_label: rejection_reason_label(decision.rejection_reason_code)
        }
      end

      def outcome_label(code)
        I18n.t("api.ai_calls.labels.visa_outcomes.#{code}", default: code.to_s.humanize)
      end

      def rejection_reason_label(code)
        return if code.blank?

        I18n.t("api.ai_calls.labels.visa_rejection_reasons.#{code}", default: code.to_s.humanize)
      end
    end
  end
end
