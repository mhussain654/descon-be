# frozen_string_literal: true

module Admin
  module BulkCalls
    # The candidates an admin can bulk-call: everyone at ONE workflow stage
    # (required, `filter[status]`), narrowed by the candidate list's own filters
    # (country, project, craft) and search, together with whether each has
    # already been called with the chosen voice.
    #
    # "Called" means a call with that voice already exists for the candidate's
    # current assignment (from a bulk batch or an automatic stage call), or one
    # is still queued in a bulk batch. That is what lets the page show what is
    # left after a batch and lets the next batch skip everyone already done.
    #
    # `called` param: 'not_called' (default), 'called' or 'all'.
    class EligibleCandidatesQuery < ApplicationQuery
      DEFAULT_PAGE_SIZE = 25
      MAX_PAGE_SIZE = 100
      CALLED_FILTERS = %w[not_called called all].freeze
      CALLED_SQL = <<~SQL.squish
        (EXISTS (SELECT 1 FROM candidate_ai_calls c
                 WHERE c.candidate_assignment_id = current_assignments.id AND c.provider_voice_id = :voice)
         OR EXISTS (SELECT 1 FROM bulk_call_batch_items i
                    JOIN bulk_call_batches b ON b.id = i.bulk_call_batch_id
                    WHERE i.candidate_assignment_id = current_assignments.id AND i.status = 'queued'
                      AND b.provider_voice_id = :voice))
      SQL
      NOT_CALLED_SQL = "NOT #{CALLED_SQL}".freeze

      attr_reader :pagination

      def initialize(scope:, params:, voice:)
        super()
        @scope = scope
        @params = params
        @voice = voice
        @pagination = {}
      end

      # One page of candidates for the list, in the order the next batch would take them.
      def call
        paginate(with_assignments(ordered(called_filtered(base_scope))))
      end

      # {matching:, called:, remaining:} for the chosen stage and filters.
      def summary
        total = base_scope.count
        called = base_scope.where(CALLED_SQL, voice: @voice.voice_id).count
        { matching: total, called:, remaining: total - called }
      end

      # The workflow stage every candidate here is at (the required `filter[status]`).
      def stage_code
        base_scope
        status_filter
      end

      # The optional narrowing filters in use (country, project, craft codes), for the batch record.
      def narrowing_filters
        raw = @params[:filter]
        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.except('status').compact_blank : {}
      end

      # The first `limit` candidates not yet called, in a stable order. Used to start a batch.
      def next_candidates(limit)
        with_assignments(ordered(not_called(base_scope))).limit(limit)
      end

      private

      def base_scope
        @base_scope ||= begin
          raise InvalidQueryParameterError.new(field: 'filter.status') if status_filter.blank?

          Admin::Candidates::IndexQuery.new(scope: @scope.where(active: true), params: @params)
                                       .filtered_scope.except(:includes)
        end
      end

      def status_filter
        raw = @params[:filter]
        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h['status'].to_s.strip : ''
      end

      def called_filtered(scope)
        case called_param
        when 'not_called' then not_called(scope)
        when 'called' then scope.where(CALLED_SQL, voice: @voice.voice_id)
        else scope
        end
      end

      def not_called(scope) = scope.where(NOT_CALLED_SQL, voice: @voice.voice_id)

      def called_param
        value = @params[:called].to_s.presence || 'not_called'
        raise InvalidQueryParameterError.new(field: 'called') unless CALLED_FILTERS.include?(value)

        value
      end

      # Only the assignments are needed (for the reference number and the current assignment), not the
      # country/project/craft/stage the candidate list preloads.
      def with_assignments(scope) = scope.includes(:candidate_assignments)

      def ordered(scope) = scope.order('current_assignments.updated_at ASC', 'candidates.id ASC')

      def paginate(scope)
        number = positive_integer(@params.dig(:page, :number), 'page.number', default: 1)
        size = positive_integer(@params.dig(:page, :size), 'page.size', default: DEFAULT_PAGE_SIZE)
        raise InvalidQueryParameterError.new(field: 'page.size') if size > MAX_PAGE_SIZE

        total_count = scope.count
        @pagination = { page: number, per_page: size, total_count:, total_pages: (total_count.to_f / size).ceil }
        scope.offset((number - 1) * size).limit(size)
      end

      def positive_integer(value, field, default:)
        return default if value.blank?

        result = Integer(value, exception: false)
        raise InvalidQueryParameterError.new(field:) unless result&.positive?

        result
      end
    end
  end
end
