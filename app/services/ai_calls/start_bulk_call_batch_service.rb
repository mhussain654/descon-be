# frozen_string_literal: true

module AiCalls
  # Starts one bulk call: takes the first `limit` candidates still to be called
  # at the query's workflow stage, records them as a BulkCallBatch, and queues
  # one background job per candidate, spaced out so RoboCall is not hit all at
  # once (see AiCalls::PlaceBulkCallItemService for what each job does).
  #
  # Refused up front, before anything is recorded: outbound calling off, outside
  # calling hours, a limit above the batch ceiling, a voice that is switched
  # off, nobody left to call, or a batch bigger than today's remaining daily
  # call budget. Two admins starting overlapping batches are serialized, so no
  # candidate is picked twice.
  class StartBulkCallBatchService < ApplicationService
    def initialize(actor:, voice:, query:, limit:, configuration: AiCalls::Configuration.new)
      @actor = actor
      @voice = voice
      @query = query
      @limit = limit
      @configuration = configuration
      @robocall_configuration = RobocallConfiguration.new
      @guard = OutboundCallGuard.new(configuration:)
    end

    def call
      ensure_startable!
      batch = BulkCallBatch.transaction { create_batch }
      enqueue(batch)
      batch
    end

    private

    def ensure_startable!
      raise AiCallVoiceNotConfiguredError unless @configuration.robocall?

      ensure_voice_and_limit!
      @guard.ensure_allowed!(actor: nil)
    end

    def ensure_voice_and_limit!
      unless @voice.active?
        raise ValidationError.new(message: I18n.t('api.errors.ai_call_bulk_voice_inactive'),
                                  field: 'bulk_call.robocall_voice_id')
      end

      ceiling = @robocall_configuration.bulk_batch_limit
      return if @limit.between?(1, ceiling)

      raise ValidationError.new(message: I18n.t('api.errors.ai_call_bulk_batch_too_large', limit: ceiling),
                                field: 'bulk_call.limit')
    end

    def create_batch
      Database::AdvisoryTransactionLock.call(scope: 'ai_calls:bulk_batch', key: "#{@voice.id}:#{@query.stage_code}")
      selection = @query.next_candidates(@limit)
      count = selection.count
      raise AiCallBulkNothingToCallError if count.zero?

      @guard.ensure_capacity_for!(count)
      batch = BulkCallBatch.create!(batch_attributes(count))
      selection.each { |candidate| add_item(batch, candidate) }
      batch
    end

    def batch_attributes(selected_count)
      {
        created_by: @actor, robocall_voice: @voice, provider_voice_id: @voice.voice_id, voice_name: @voice.name_en,
        workflow_stage_code: @query.stage_code, filters: @query.narrowing_filters, requested_limit: @limit,
        selected_count:
      }
    end

    def add_item(batch, candidate)
      batch.items.create!(candidate:, candidate_assignment: candidate.current_assignment)
    end

    # After the transaction commits (Solid Queue writes to its own database, so
    # a job enqueued inside it would outlive a rollback).
    def enqueue(batch)
      spacing = @robocall_configuration.bulk_call_spacing_seconds
      batch.items.order(:id).each_with_index do |item, index|
        PlaceBulkCallItemJob.set(wait: (index * spacing).seconds).perform_later(item.id)
      end
    end
  end
end
