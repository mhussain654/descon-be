# frozen_string_literal: true

module Admin
  class DocumentReviewQueueQuery < ApplicationQuery
    PRELOADS = [
      { candidate_assignment: %i[candidate country craft project] },
      { submission_items: :candidate_document }
    ].freeze

    SUMMARY_STATUSES = %w[pending_review verified rejected expired_pcc near_expiry_pcc].freeze

    attr_reader :pagination

    def initialize(scope:, params:)
      super()
      @scope = scope
      @filters = DocumentReviewQueueParams.new(params:)
      @pagination = {}
    end

    def call
      paginated_scope = paginate(ordered_scope)
      paginated_scope.preload(*PRELOADS)
    end

    # Distinct-candidate counts per review bucket, scoped by every filter
    # except `status` (so the chip counts describe "if you filtered by this
    # status" the same way the list itself would, matching the ticket's
    # "counts that reconcile with the review queue" requirement). Distinct
    # by candidate, not submission -- a candidate can have more than one
    # submission row over time (e.g. rejection then resubmission), and this
    # is new reporting code with no existing behavior to preserve, so it's
    # built correctly from the start.
    def summary
      SUMMARY_STATUSES.index_with { |status| distinct_candidate_count(status) }
    end

    private

    def distinct_candidate_count(status)
      DocumentReviewQueueStatusFilter.new(scope: scope_without_status, statuses: [status]).call
                                     .joins(candidate_assignment: :candidate)
                                     .distinct
                                     .count('candidates.id')
    end

    def ordered_scope
      filtered_scope.order(submitted_at: :desc, public_id: :asc)
    end

    def filtered_scope
      DocumentReviewQueueStatusFilter.new(scope: scope_without_status, statuses: @filters.statuses).call
    end

    def scope_without_status
      scope = @scope
      scope = filter_candidate_public_id(scope)
      scope = filter_country_code(scope)
      scope = filter_project_code(scope)
      scope = filter_submitted_from(scope)
      filter_submitted_to(scope)
    end

    def filter_candidate_public_id(scope)
      return scope if @filters.candidate_public_id.blank?

      scope.joins(candidate_assignment: :candidate).where(candidates: { public_id: @filters.candidate_public_id })
    end

    def filter_country_code(scope)
      return scope if @filters.country_code.blank?

      scope.joins(:candidate_assignment).where(
        candidate_assignments: { country_id: Country.where(code: @filters.country_code).select(:id) }
      )
    end

    def filter_project_code(scope)
      return scope if @filters.project_code.blank?

      scope.joins(:candidate_assignment).where(
        candidate_assignments: { project_id: Project.where(code: @filters.project_code).select(:id) }
      )
    end

    def filter_submitted_from(scope)
      return scope if @filters.submitted_from.blank?

      scope.where(candidate_document_submissions: { submitted_at: @filters.submitted_from.. })
    end

    def filter_submitted_to(scope)
      return scope if @filters.submitted_to.blank?

      scope.where(candidate_document_submissions: { submitted_at: ..@filters.submitted_to })
    end

    def paginate(scope)
      total_count = scope.count
      total_pages = total_count.zero? ? 0 : (total_count.to_f / @filters.page_size).ceil
      @pagination = {
        page: @filters.page_number,
        per_page: @filters.page_size,
        total_count:,
        total_pages:
      }

      scope.offset((@filters.page_number - 1) * @filters.page_size).limit(@filters.page_size)
    end
  end
end
