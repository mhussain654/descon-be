# frozen_string_literal: true

module AiCalls
  module Tools
    class GetQvcStatus < VerifiedDataTool
      private

      def data
        attempt = assignment.candidate_qvc_attempts.latest_first.first
        return { status: 'not_scheduled', status_label: status_label('not_scheduled') } if attempt.blank?

        serialized = ::CandidateWorkflows::QvcAttemptSerializer.new(attempt).as_json
        serialized.merge(status_label: status_label(serialized[:status]))
      end

      def status_label(status_code)
        I18n.t("api.ai_calls.labels.qvc_statuses.#{status_code}", default: status_code.to_s.humanize)
      end
    end
  end
end
