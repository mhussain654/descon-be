# frozen_string_literal: true

module CandidateWorkflows
  module FlightDetails
    # Staff reject a candidate's boarding pass photo that isn't a valid boarding
    # pass for their flight, with a reason the candidate sees in the app. The
    # photo is kept for the record, but no longer confirms departure, and the
    # candidate gets an SMS and BOARDING_PASS_DAYS_AFTER_REJECTION days to
    # upload another, even if the normal upload window has closed.
    class BoardingPassRejectionService < ApplicationService
      FIELD = 'boarding_pass_rejection.reason'
      MAX_REASON_LENGTH = 500

      def initialize(actor:, candidate:, reason:, request_id:)
        @actor = actor
        @candidate = candidate
        @reason = reason.to_s.strip
        @request_id = request_id
      end

      def call
        detail = flight_detail
        validate!(detail)

        CandidateFlightDetail.transaction do
          reject!(detail)
          create_audit_event!(detail)
          schedule_sms!(detail)
        end
        detail
      end

      private

      def reject!(detail)
        detail.lock!
        raise BoardingPassAlreadyRejectedError if detail.boarding_pass_rejected?

        detail.update!(boarding_pass_rejected_at: Time.current, boarding_pass_rejected_by: @actor,
                       boarding_pass_rejection_reason: @reason)
      end

      def flight_detail
        @candidate.current_assignment&.candidate_flight_detail || raise(NotFoundError)
      end

      def validate!(detail)
        raise BoardingPassNotUploadedError unless detail.boarding_pass_uploaded? && detail.boarding_pass.attached?
        raise invalid_reason('rejection_reason_required') if @reason.blank?
        raise invalid_reason('boarding_pass_rejection_reason_too_long') if @reason.length > MAX_REASON_LENGTH
      end

      def invalid_reason(message_key)
        ValidationError.new(field: FIELD, message: I18n.t("api.errors.#{message_key}"))
      end

      # The client's approved "document rejected" SMS, naming the boarding pass.
      def schedule_sms!(detail)
        locale = CandidateSms::ScheduleDelivery.locale_for(@candidate)
        CandidateSms::ScheduleDelivery.call(
          assignment: detail.candidate_assignment, message_code: 'document_rejected',
          dedupe_key: "boarding_pass_rejected:#{detail.id}:#{detail.boarding_pass_uploaded_at.to_i}",
          variables: { document: I18n.t('api.boarding_pass_document_name', locale:) }
        )
      end

      def create_audit_event!(detail)
        AuditEvent.create!(
          actor: @actor, candidate: @candidate, candidate_assignment: detail.candidate_assignment,
          entity_type: 'CandidateFlightDetail', entity_id: detail.id,
          action_code: 'candidate_boarding_pass_rejected', request_id: @request_id,
          metadata: { actor_public_id: @actor.public_id, candidate_public_id: @candidate.public_id,
                      flight_detail_public_id: detail.public_id },
          occurred_at: detail.boarding_pass_rejected_at
        )
      end
    end
  end
end
