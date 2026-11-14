# frozen_string_literal: true

module Admin
  module WorkflowCorrections
    # The Overview tab's correction boxes: for the medical appointment, the QVC
    # appointment and the flight, the current values, whether a developer may
    # change them (and if not, why), and the latest changes made.
    class WorkflowCorrectionSerializer
      RECENT_CHANGES_LIMIT = 5
      ACTION_CODES = {
        medical_appointment: 'medical_appointment_corrected',
        qvc_appointment: 'qvc_appointment_corrected',
        flight_detail: 'flight_detail_corrected'
      }.freeze

      def initialize(candidate:, assignment:)
        @candidate = candidate
        @assignment = assignment
        @status = ::CandidateWorkflows::Corrections::Status.new(assignment)
      end

      def as_json(*)
        {
          candidate_id: @candidate.public_id,
          assignment_id: @assignment&.public_id,
          medical_appointment: box(:medical_appointment, @status.medical_values, @status.medical_blocked_reason),
          qvc_appointment: box(:qvc_appointment, @status.qvc_values, @status.qvc_blocked_reason),
          flight_detail: box(:flight_detail, @status.flight_values, @status.flight_blocked_reason)
        }
      end

      private

      def box(kind, values, blocked_reason)
        blocked_reason ||= ::CandidateWorkflows::Corrections::Status::BLOCKED_NOT_RECORDED if @assignment.blank?
        { values:, editable: blocked_reason.nil?, blocked_reason:, recent_changes: recent_changes(kind) }
      end

      def recent_changes(kind)
        return [] if @assignment.blank?

        ::AuditEvent.where(candidate_assignment: @assignment, action_code: ACTION_CODES.fetch(kind))
                    .includes(:actor).order(occurred_at: :desc, id: :desc).limit(RECENT_CHANGES_LIMIT)
                    .map { |event| serialized_change(event) }
      end

      def serialized_change(event)
        {
          occurred_at: event.occurred_at.utc.iso8601,
          reason: event.note,
          changes: event.metadata['changes'] || {},
          sms_requested: event.metadata['sms_requested'],
          actor: event.actor && { id: event.actor.public_id, role: event.actor.role }
        }
      end
    end
  end
end
