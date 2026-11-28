# frozen_string_literal: true

module CandidateSms
  # Changes which sender a candidate's SMS go out from (Candidate#sms_sender)
  # and audits the change. Choosing the sender already set is a no-op.
  class UpdateSender < ApplicationService
    def initialize(candidate:, sms_sender:, actor:, request_id:)
      @candidate = candidate
      @sms_sender = sms_sender.to_s
      @actor = actor
      @request_id = request_id
    end

    def call
      validate!
      return @candidate if @candidate.sms_sender == @sms_sender

      Candidate.transaction do
        previous = @candidate.sms_sender
        @candidate.update!(sms_sender: @sms_sender)
        create_audit_event!(previous)
      end

      @candidate
    end

    private

    def validate!
      return if Candidate.sms_senders.key?(@sms_sender)

      raise ValidationError.new(field: 'sms_sender.sender', message: I18n.t('api.errors.sms_sender_invalid'))
    end

    def create_audit_event!(previous)
      AuditEvent.create!(
        actor: @actor, candidate: @candidate, entity_type: 'Candidate', entity_id: @candidate.id,
        action_code: 'candidate_sms_sender_changed', request_id: @request_id,
        metadata: { candidate_public_id: @candidate.public_id, from: previous, to: @sms_sender },
        occurred_at: Time.current
      )
    end
  end
end
