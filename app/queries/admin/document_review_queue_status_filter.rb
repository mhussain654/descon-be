# frozen_string_literal: true

module Admin
  class DocumentReviewQueueStatusFilter < ApplicationQuery
    PENDING_REQUIRED_COUNT_SQL = <<~SQL.squish.freeze
      SUM(
        CASE
          WHEN candidate_document_submission_items.required = TRUE
            AND candidate_documents.status_code = 'under_verification'
          THEN 1
          ELSE 0
        END
      )
    SQL
    REJECTED_REQUIRED_COUNT_SQL = <<~SQL.squish.freeze
      SUM(
        CASE
          WHEN candidate_document_submission_items.required = TRUE
            AND candidate_documents.status_code = 'rejected'
          THEN 1
          ELSE 0
        END
      )
    SQL
    REQUIRED_TOTAL_SQL = <<~SQL.squish.freeze
      SUM(CASE WHEN candidate_document_submission_items.required = TRUE THEN 1 ELSE 0 END)
    SQL
    VERIFIED_REQUIRED_COUNT_SQL = <<~SQL.squish.freeze
      SUM(
        CASE
          WHEN candidate_document_submission_items.required = TRUE
            AND candidate_documents.status_code = 'verified'
          THEN 1
          ELSE 0
        END
      )
    SQL
    EXPIRED_PCC_COUNT_SQL = <<~SQL.squish.freeze
      SUM(
        CASE
          WHEN document_types.code = '#{CandidateDocument::PCC_REQUIREMENT_CODE}'
            AND candidate_documents.expires_on < CURRENT_DATE
          THEN 1
          ELSE 0
        END
      )
    SQL

    def initialize(scope:, statuses:)
      super()
      @scope = scope
      @statuses = statuses
    end

    def call
      filtered_scope = aggregate_scope.having(having_clause)
      @scope.where(id: filtered_scope.select(:id))
    end

    private

    def aggregate_scope
      @scope
        .left_outer_joins(submission_items: { candidate_document: :document_type })
        .group('candidate_document_submissions.id')
    end

    def having_clause
      @statuses.map { |status| status_clause(status) }.join(' OR ')
    end

    def status_clause(status)
      {
        'changes_required' => "(#{REJECTED_REQUIRED_COUNT_SQL} > 0)",
        'rejected' => "(#{REJECTED_REQUIRED_COUNT_SQL} > 0)",
        'verified' => "(#{REQUIRED_TOTAL_SQL} > 0 AND #{VERIFIED_REQUIRED_COUNT_SQL} = #{REQUIRED_TOTAL_SQL})",
        'partially_reviewed' => partial_review_clause,
        'pending_review' => pending_review_clause,
        'expired_pcc' => "(#{EXPIRED_PCC_COUNT_SQL} > 0)",
        'near_expiry_pcc' => "(#{near_expiry_pcc_count_sql} > 0)"
      }.fetch(status) { raise InvalidQueryParameterError.new(field: 'filter.status') }
    end

    # The near-expiry window comes from the same
    # `PCC_NEAR_EXPIRY_DAYS`-backed threshold the candidate-facing
    # compliance_status already uses (CandidateDocuments::PoliceCharacterCompliance)
    # -- built per-call rather than as a frozen constant since it's not a
    # fixed value, but it is never user input (validated non-negative at the
    # source), so direct interpolation into the SQL fragment is safe.
    def near_expiry_pcc_count_sql
      <<~SQL.squish
        SUM(
          CASE
            WHEN document_types.code = '#{CandidateDocument::PCC_REQUIREMENT_CODE}'
              AND candidate_documents.expires_on BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '#{CandidateDocument.pcc_near_expiry_days} days')
            THEN 1
            ELSE 0
          END
        )
      SQL
    end

    def partial_review_clause
      "(#{REJECTED_REQUIRED_COUNT_SQL} = 0 AND #{PENDING_REQUIRED_COUNT_SQL} > 0 " \
        "AND #{VERIFIED_REQUIRED_COUNT_SQL} > 0)"
    end

    def pending_review_clause
      "(#{REJECTED_REQUIRED_COUNT_SQL} = 0 AND #{PENDING_REQUIRED_COUNT_SQL} > 0 " \
        "AND #{VERIFIED_REQUIRED_COUNT_SQL} = 0)"
    end
  end
end
