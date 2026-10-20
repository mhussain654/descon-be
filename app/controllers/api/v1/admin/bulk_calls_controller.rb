# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Bulk voice calls: list the candidates at one workflow stage with whether
      # each was already called with a chosen voice (`candidates`), start a batch
      # for the next few of them (`create`), and read batches (`index`, `show`).
      # Starting a batch only queues the calls (see AiCalls::StartBulkCallBatchService).
      class BulkCallsController < ProtectedStaffController
        include IdempotentRequestHandling

        RECENT_BATCH_LIMIT = 50
        CREATE_PARAMS = [:robocall_voice_id, :workflow_stage_code, :limit, :search,
                         { filter: %i[country_code project_code craft_code] }].freeze

        def index
          authorize ::BulkCallBatch, policy_class: ::Admin::BulkCallPolicy

          batches = batch_scope.includes(:robocall_voice,
                                         :created_by).order(created_at: :desc).limit(RECENT_BATCH_LIMIT)
          counts = counts_by_batch(batches.map(&:id))
          render_success(data: batches.map { |batch| serialized_batch(batch, counts.fetch(batch.id, {})) })
        end

        def show
          authorize ::BulkCallBatch, policy_class: ::Admin::BulkCallPolicy

          batch = batch_scope.find_by!(public_id: params.expect(:id))

          items = batch.items.includes(:candidate, :candidate_ai_call).order(:id)
          render_success(
            data: serialized_batch(batch, batch.status_counts)
                  .merge(items: items.map { |item| ::Admin::BulkCalls::BatchItemSerializer.new(item).as_json })
          )
        end

        def candidates
          authorize ::BulkCallBatch, policy_class: ::Admin::BulkCallPolicy

          voice = find_voice(params.expect(:robocall_voice_id))
          query = eligible_query(voice:, query_params: params)
          rows = ::Admin::BulkCalls::CandidateRowsSerializer.new(query.call, voice:).as_json
          render_collection(data: rows, pagination: query.pagination, meta: candidates_meta(query))
        end

        def create
          authorize ::BulkCallBatch, policy_class: ::Admin::BulkCallPolicy

          render_idempotent_response(scope: 'admin.bulk_calls.create', subject: current_user,
                                     fingerprint: create_params.to_h.to_json, required: true) do
            batch = start_batch
            success_payload(data: serialized_batch(batch, batch.status_counts), status: :created)
          end
        end

        private

        def candidates_meta(query)
          { summary: query.summary, batch_limit: robocall_configuration.bulk_batch_limit,
            applied_filters: query.narrowing_filters.merge('status' => query.stage_code) }
        end

        def start_batch
          voice = find_voice(create_params.fetch(:robocall_voice_id))
          ::AiCalls::StartBulkCallBatchService.call(
            actor: current_user, voice:, limit: requested_limit,
            query: eligible_query(voice:, query_params: create_query_params)
          )
        end

        def eligible_query(voice:, query_params:)
          ::Admin::BulkCalls::EligibleCandidatesQuery.new(
            scope: policy_scope(::Candidate, policy_scope_class: ::Admin::CandidatePolicy::Scope),
            params: query_params, voice:
          )
        end

        # The create body spelled the way the candidate list's filters are, so the same query serves both.
        def create_query_params
          filter = create_params[:filter].to_h.merge('status' => create_params[:workflow_stage_code])
          ActionController::Parameters.new(filter:, search: create_params[:search], called: 'not_called')
        end

        def create_params
          @create_params ||= params.expect(bulk_call: CREATE_PARAMS)
        end

        def requested_limit
          Integer(create_params[:limit], exception: false) || raise(ValidationError.new(field: 'bulk_call.limit'))
        end

        def find_voice(public_id)
          ::RobocallVoice.find_by!(public_id:)
        end

        def batch_scope
          policy_scope(::BulkCallBatch, policy_scope_class: ::Admin::BulkCallPolicy::Scope)
        end

        def counts_by_batch(batch_ids)
          ::BulkCallBatchItem.where(bulk_call_batch_id: batch_ids).group(:bulk_call_batch_id, :status).count
                             .each_with_object(Hash.new do |hash, key|
                                                 hash[key] = {}
                                               end) do |((batch_id, status), count), result|
            result[batch_id][status] = count
          end
        end

        def serialized_batch(batch, counts)
          ::Admin::BulkCalls::BatchSerializer.new(batch, counts:).as_json
        end

        def robocall_configuration = ::AiCalls::RobocallConfiguration.new
      end
    end
  end
end
