# frozen_string_literal: true

module AiCalls
  module Tools
    class GetProtectionStatus < VerifiedDataTool
      private

      def data
        record = assignment.candidate_protection_record
        return { status: 'not_yet_scheduled', status_label: status_label('not_yet_scheduled') } if record.blank?

        code = status_code(record)
        serialized = ::CandidateWorkflows::ProtectionSerializer.new(record).as_json
        serialized.merge(status: code, status_label: status_label(code))
      end

      # A protection record's milestone fields (appeared/protected/ready_to_fly)
      # are set incrementally over time -- their raw presence/absence doesn't
      # say anything speakable on its own, so this derives one explicit status
      # the agent can state directly instead of inferring meaning from dates.
      def status_code(record)
        return 'ready_to_fly' if record.ready_to_fly_at.present?
        return 'protected_awaiting_flight' if record.protected_on.present?
        return 'appeared_awaiting_outcome' if record.appeared_on.present?

        'not_yet_scheduled'
      end

      def status_label(code)
        I18n.t("api.ai_calls.labels.protection_statuses.#{code}", default: code.to_s.humanize)
      end
    end
  end
end
