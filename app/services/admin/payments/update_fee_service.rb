# frozen_string_literal: true

module Admin
  module Payments
    # Fee writes share checkout's candidate -> assignment lock order. Default
    # updates lock the singleton; checkout snapshots the resolved amount once.
    class UpdateFeeService < ApplicationService
      def initialize(**params)
        @actor, @record, @amount = params.values_at(:actor, :record, :amount)
        @expected_version = params[:expected_version]
        @reason = params[:reason].to_s.strip
        @request_id, @candidate = params.values_at(:request_id, :candidate)
      end

      def call
        raise ForbiddenError unless @actor&.active_staff_account? && @actor.permission?('manage_payments')

        validate_payload!
        persist_fee!
        @record
      end

      private

      def persist_fee!
        @record.class.transaction do
          @candidate&.lock!
          @record.lock!
          validate_state!
          update_record!
          record_audit!
        end
      end

      def validate_payload!
        if @reason.empty? || @reason.length > 500
          raise ValidationError.new(field: 'fee.reason', message: I18n.t('api.errors.fee_reason_required'))
        end
        raise ValidationError.new(field: 'fee.expected_version') unless @expected_version.to_s.match?(/\A\d+\z/)

        validate_amount!
      end

      def validate_amount!
        return if @amount.nil? && @candidate.present?
        return if @amount.to_s.match?(/\A\d{1,8}(?:\.\d{1,2})?\z/) && BigDecimal(@amount.to_s).positive?

        raise ValidationError.new(field: 'fee.amount', message: I18n.t('api.errors.fee_amount_invalid'))
      end

      def validate_state!
        version = @candidate ? @record.fee_version : @record.lock_version
        raise FeeChangeConflictError unless version == @expected_version.to_i
        return unless @candidate

        raise FeeChangeConflictError if @candidate.current_assignment&.id != @record.id
        return unless ::Payments::FeeResolver.committed_payment(@record)

        raise FeeChangeConflictError.new(code: 'fee_locked')
      end

      def update_record!
        if @candidate
          @record.update!(onboarding_fee_amount: @amount, fee_version: @record.fee_version + 1)
        else
          @record.update!(amount: @amount, updated_by: @actor)
        end
      end

      def record_audit!
        AuditEvent.create!(
          actor: @actor, candidate: @candidate, candidate_assignment: @candidate ? @record : nil,
          entity_type: @record.class.name, entity_id: @record.id,
          action_code: @candidate ? 'candidate_fee_updated' : 'default_fee_updated',
          request_id: @request_id, occurred_at: Time.current,
          metadata: { reason: @reason, changes: @record.saved_changes.slice('amount', 'onboarding_fee_amount') }
        )
      end
    end
  end
end
