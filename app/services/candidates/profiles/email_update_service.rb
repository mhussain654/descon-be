# frozen_string_literal: true

module Candidates
  module Profiles
    # Sets, changes or clears the candidate's own email address (stored
    # lowercased; blank clears it) and records an audit event when it changes.
    # The address itself is not put in the audit metadata.
    class EmailUpdateService < ApplicationService
      def initialize(candidate:, email:, request_id:)
        @candidate = candidate
        @email = ::Candidate.normalized_email(email)
        @request_id = request_id
      end

      def call
        raise InvalidEmailError if @email && !::Candidate.valid_email?(@email)
        return @candidate if @candidate.email == @email

        ::Candidate.transaction do
          @candidate.update!(email: @email)
          create_audit_event!
        end
        @candidate
      end

      private

      def create_audit_event!
        AuditEvent.create!(
          actor: nil, candidate: @candidate, entity_type: 'Candidate', entity_id: @candidate.id,
          action_code: 'candidate_email_updated', request_id: @request_id,
          metadata: { candidate_public_id: @candidate.public_id, email_present: @email.present? },
          occurred_at: Time.current
        )
      end
    end
  end
end
