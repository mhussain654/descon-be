# frozen_string_literal: true

module Candidates
  module Documents
    # Rejects a CNIC or passport upload straight away when OCR shows it isn't one
    # (a selfie, a random photo, another document, or a photo too blurry to read),
    # so staff never have to review it. Only when the developer-only
    # `document_identity_check` App Settings switch is on, and only when OCR found
    # no dates and none of the printed ID markers (DocumentOcr::IdentityMarkers):
    # a real ID whose dates were hard to read is always left for staff.
    #
    # The candidate sees the reason in the app, gets the "document rejected" SMS,
    # and uploads again. Staff can still approve a submitted one they disagree
    # with (Admin::DocumentReviews::DecisionService). Never rejects the same
    # requirement automatically twice in a row: if the next upload fails the check
    # too, it goes to staff, so a genuine but unusual document is never stuck.
    class AutomaticRejectionService < ApplicationService
      REJECTABLE_STATUSES = %w[uploaded under_verification].freeze
      REJECTED_IDENTITY_RESULTS = %w[other_text no_text].freeze

      # `identity`: the best IdentityMarkers result over the pages OCR read.
      def initialize(document:, identity:)
        @document = document
        @identity = identity
      end

      def call
        return unless REJECTED_IDENTITY_RESULTS.include?(@identity)
        return unless AppFeatureSetting.enabled?(:document_identity_check)

        CandidateDocument.transaction do
          document = CandidateDocument.current_version.lock.find_by(id: @document.id)
          next unless rejectable?(document)

          reject!(document)
          create_audit_event!(document)
          schedule_sms!(document)
        end
      end

      private

      def rejectable?(document)
        document.present? && REJECTABLE_STATUSES.include?(document.status_code) && !previous_version_rejected?(document)
      end

      def previous_version_rejected?(document)
        CandidateDocument.where(candidate_assignment_id: document.candidate_assignment_id,
                                document_type_id: document.document_type_id)
                         .where.not(id: document.id)
                         .order(uploaded_at: :desc, id: :desc)
                         .first&.rejected_automatically? || false
      end

      def reject!(document)
        document.update!(status_code: 'rejected', rejected_automatically: true, verified_at: Time.current,
                         verified_by: nil, rejection_reason: reason_for(document))
      end

      # Written in the candidate's language, like a staff member's reason would be.
      def reason_for(document)
        locale = CandidateSms::ScheduleDelivery.locale_for(document.candidate_assignment.candidate)
        I18n.t("api.document_identity_check.#{@identity}", locale:, document: document_name(document, locale))
      end

      def document_name(document, locale)
        document.document_type.public_send(locale == 'ur' ? :name_ur : :name_en)
      end

      def schedule_sms!(document)
        locale = CandidateSms::ScheduleDelivery.locale_for(document.candidate_assignment.candidate)
        CandidateSms::ScheduleDelivery.call(
          assignment: document.candidate_assignment, message_code: 'document_rejected',
          dedupe_key: "document_rejected:#{document.id}",
          variables: { document: document_name(document, locale) }
        )
      end

      def create_audit_event!(document)
        AuditEvent.create!(
          actor: nil, candidate: document.candidate_assignment.candidate,
          candidate_assignment: document.candidate_assignment, entity_type: 'CandidateDocument',
          entity_id: document.id, action_code: 'candidate_document_rejected_automatically', request_id: nil,
          metadata: { document_public_id: document.public_id, identity_check: @identity },
          occurred_at: document.verified_at
        )
      end
    end
  end
end
