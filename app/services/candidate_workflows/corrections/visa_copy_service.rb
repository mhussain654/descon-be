# frozen_string_literal: true

module CandidateWorkflows
  module Corrections
    # Replaces the visa copy on a candidate's latest (issued) visa decision --
    # for a copy that was uploaded wrongly, or whose file never reached
    # storage. The decision itself (outcome, date) and the candidate's stage
    # stay as they are. No SMS: the candidate's visa outcome has not changed.
    class VisaCopyService < BaseService
      # The new file is checked and stored before the correction's transaction;
      # see UploadedFileBlob.
      def call
        validate_actor!
        VisaDecisions::VisaCopyValidator.call(visa_copy: @values[:visa_copy])
        UploadedFileBlob.storing(@values[:visa_copy]) do |blob|
          @visa_copy_blob = blob
          super
        end
      end

      private

      def blocked_reason = status.visa_blocked_reason
      def audited_record = status.visa_decision
      def action_code = 'visa_copy_corrected'
      def sms_message_code = nil
      def sms_variables = nil

      def apply!
        decision = status.visa_decision
        previous = status.visa_values
        decision.visa_copy.attach(@visa_copy_blob)
        { 'visa_copy' => [previous_state(previous), 'replaced'] }
      end

      def previous_state(values)
        return 'none' unless values[:has_visa_copy]

        values[:visa_copy_stored] == false ? 'missing_from_storage' : 'attached'
      end
    end
  end
end
