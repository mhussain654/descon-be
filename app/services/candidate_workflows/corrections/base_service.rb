# frozen_string_literal: true

module CandidateWorkflows
  module Corrections
    # Shared steps for a developer correcting a candidate's recorded details:
    # only the developer-only `correct_workflow_details` permission may do it, a
    # reason is required, the candidate stays at the same stage, the change is
    # an audit event (old and new values, the reason), and the candidate is
    # texted about it unless the developer unticked "Send SMS". Subclasses
    # name the record (`blocked_reason`), apply the change (`apply!`, returning
    # { field => [old, new] }) and build the SMS (`sms_variables`). `values`
    # holds the new values plus `reason` and `notify_candidate` (default true).
    class BaseService < ApplicationService
      REASON_MAX_LENGTH = 500

      def initialize(actor:, candidate:, request_id:, values:)
        @actor = actor
        @candidate = candidate
        @request_id = request_id
        @values = values.to_h.with_indifferent_access
        @reason = @values.delete(:reason).to_s.strip.presence
        @notify_candidate = ActiveModel::Type::Boolean.new.cast(@values.delete(:notify_candidate)) != false
      end

      def call
        validate_actor!
        validate_reason!

        CandidateAssignment.transaction do
          @assignment = locked_assignment
          @status = Status.new(@assignment)
          raise_not_allowed! if blocked_reason.present?

          record_change!(apply!)
        end
        @assignment
      end

      private

      attr_reader :assignment, :status

      def validate_actor!
        raise InactiveAccountError unless @actor&.active_staff_account?
        raise ForbiddenError unless @actor.permission?('correct_workflow_details')
      end

      def validate_reason!
        return if @reason.present? && @reason.length <= REASON_MAX_LENGTH

        raise ValidationError.new(field: 'workflow_correction.reason',
                                  message: I18n.t('api.errors.workflow_correction_reason_required'))
      end

      def locked_assignment
        candidate = Candidate.lock.find(@candidate.id)
        assignment_id = candidate.current_assignment&.id
        raise NoCurrentAssignmentError if assignment_id.blank?

        CandidateAssignment.lock.find(assignment_id)
      end

      def raise_not_allowed!
        raise ValidationError.new(field: 'workflow_correction',
                                  message: I18n.t("api.errors.workflow_correction_#{blocked_reason}"))
      end

      def record_change!(changes)
        if changes.empty?
          raise ValidationError.new(field: 'workflow_correction',
                                    message: I18n.t('api.errors.workflow_correction_no_changes'))
        end

        audit_event = create_audit_event!(changes)
        assignment.update!(updated_at: Time.current)
        notify!(audit_event)
      end

      def create_audit_event!(changes)
        AuditEvent.create!(
          actor: @actor, candidate: assignment.candidate, candidate_assignment: assignment,
          entity_type: audited_record.class.name, entity_id: audited_record.id, action_code:,
          request_id: @request_id, occurred_at: Time.current, note: @reason,
          metadata: { changes:, sms_requested: @notify_candidate }
        )
      end

      def notify!(audit_event)
        variables = sms_variables
        return unless @notify_candidate && variables

        CandidateSms::ScheduleDelivery.call(assignment:, message_code: sms_message_code,
                                            dedupe_key: "#{sms_message_code}:#{audit_event.id}", variables:)
      end

      # { field => [old, new] } for each field whose value changed.
      def changed_fields(before, after)
        after.each_with_object({}) do |(field, value), changes|
          changes[field.to_s] = [before[field], value] unless before[field] == value
        end
      end

      def text(field) = @values[field].to_s.squish.presence

      def validate_length!(field, value, maximum)
        return if value.nil? || value.length <= maximum

        raise_invalid!(field)
      end

      def validate_time!(field, value)
        return if value.nil? || value.match?(MedicalAppointmentSetting::TIME_FORMAT)

        raise ValidationError.new(field: "workflow_correction.#{field}",
                                  message: I18n.t('api.errors.workflow_transition_evidence_time_invalid'))
      end

      def parse_date!(field, value, required: false)
        return raise_invalid!(field) if value.nil? && required
        return if value.nil?

        Date.iso8601(value)
      rescue ArgumentError
        raise ValidationError.new(field: "workflow_correction.#{field}",
                                  message: I18n.t('api.errors.workflow_transition_evidence_date_invalid'))
      end

      def raise_invalid!(field)
        raise ValidationError.new(field: "workflow_correction.#{field}",
                                  message: I18n.t('api.errors.workflow_transition_evidence_value_invalid'))
      end
    end
  end
end
