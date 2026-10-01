# frozen_string_literal: true

module AiCalls
  module Tools
    class GetFlightInformation < VerifiedDataTool
      private

      def data
        detail = assignment.candidate_flight_detail
        return { status: 'not_yet_available', status_label: status_label('not_yet_available') } if detail.blank?

        code = detail.mobilized? ? 'mobilized' : 'flight_scheduled'
        serialized = ::CandidateWorkflows::FlightDetailSerializer.new(detail).as_json
        serialized.merge(status: code, status_label: status_label(code))
      end

      def status_label(code)
        I18n.t("api.ai_calls.labels.flight_statuses.#{code}", default: code.to_s.humanize)
      end
    end
  end
end
