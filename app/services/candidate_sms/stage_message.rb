# frozen_string_literal: true

module CandidateSms
  # Queues the progress SMS, if any, for a candidate entering a workflow stage,
  # using what the transition just recorded (medical date, QVC attempt, visa
  # decision, flight). Called by CandidateWorkflows::TransitionSideEffectRecorder
  # after those records exist. Stages not handled here send nothing; the fee
  # stage's SMS is queued by Payments::IssueFeeVoucherService instead.
  class StageMessage < ApplicationService
    TIME_ZONE = 'Asia/Karachi'

    def initialize(history_entry:, context:, evidence:)
      @history_entry = history_entry
      @context = context
      @evidence = evidence
    end

    def call
      message = stage_message || action_message
      return if message.blank?

      ScheduleDelivery.call(assignment:, **message)
    end

    private

    # rubocop:disable Metrics/CyclomaticComplexity -- one branch per stage that sends an SMS
    def stage_message
      case @context.fetch(:destination_stage).code
      when 'documents_pending' then stage_entry('registered')
      when 'qvc_appointment_booked' then qvc_appointment_message
      when 'visa_issued_or_rejected' then visa_message
      when 'protection_call' then protection_call_message
      when 'appeared_for_protection' then stage_entry('ticket_and_flight_details')
      when 'ticket_handover' then stage_entry('ticket_handover')
      when 'flight_details_uploaded' then flight_message
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    # The medical stages differ per country, so they are matched by what they record.
    def action_message
      case @context[:destination_process_stage]&.action_type
      when 'medical_appointment' then medical_appointment_message
      when 'medical_outcome' then medical_unfit_message
      end
    end

    # A stage is entered once per assignment, so its history entry names the event.
    def stage_entry(message_code, **variables)
      { message_code:, dedupe_key: "#{message_code}:#{@history_entry.id}", variables: }
    end

    # The date is optional on these stages, and the SMS is only worth sending with it.
    def medical_appointment_message
      date = date_from('medical_appointment_date')
      stage_entry('medical_appointment', date:) if date
    end

    # A fit candidate hears about the fee instead (CandidateWorkflows::FeeStageOpener).
    def medical_unfit_message
      stage_entry('medical_unfit') if @evidence['medical_outcome_code'] == 'unfit'
    end

    def qvc_appointment_message
      attempt = assignment.candidate_qvc_attempts.order(:attempt_number).last
      self.class.qvc_appointment(attempt)
    end

    def visa_message
      decision = assignment.candidate_visa_decisions.order(:id).last
      self.class.visa_decision(decision)
    end

    # Only a protection call that is still to happen has a date to tell the candidate.
    def protection_call_message
      return unless @evidence['protection_call_status'] == 'scheduled'

      stage_entry('protection_call', date: date_from('protection_call_on'))
    end

    def flight_message
      departure = assignment.candidate_flight_detail.flight_departure_at.in_time_zone(TIME_ZONE)
      detail = assignment.candidate_flight_detail
      stage_entry('flight_details', airline: detail.airline, flight: detail.flight_number, sector: detail.sector.to_s,
                                    date: ScheduleDelivery.format_date(departure), time: departure.strftime('%H:%M'))
    end

    def date_from(field)
      value = @evidence[field]
      ScheduleDelivery.format_date(Date.iso8601(value)) if value.present?
    end

    def assignment = @context.fetch(:assignment)

    class << self
      # Also used when a follow-up QVC appointment is booked without a stage change.
      def qvc_appointment(attempt)
        { message_code: 'qvc_appointment', dedupe_key: "qvc_appointment:#{attempt.id}",
          variables: { date: ScheduleDelivery.format_date(attempt.appointment_date) } }
      end

      # Also used for a re-decision (re-application or appeal) without a stage change.
      # An issued visa names the country it is for.
      def visa_decision(decision)
        { message_code: "visa_#{decision.outcome_code}", dedupe_key: "visa_decision:#{decision.id}",
          variables: decision.outcome_code == 'issued' ? { country: visa_country(decision) } : {} }
      end

      private

      def visa_country(decision)
        assignment = decision.candidate_assignment
        ScheduleDelivery.country_name(assignment, ScheduleDelivery.locale_for(assignment.candidate))
      end
    end
  end
end
