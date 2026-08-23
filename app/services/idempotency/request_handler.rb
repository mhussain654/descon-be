# frozen_string_literal: true

module Idempotency
  class RequestHandler < ApplicationService
    KEY_FORMAT = /\A[a-zA-Z0-9:_-]{1,128}\z/
    DEFAULT_EXPIRY = 12.hours

    Result = Struct.new(:payload, :replayed, keyword_init: true)

    def initialize(key:, scope:, request_context:, subject: nil, expires_in: DEFAULT_EXPIRY)
      @key = key.to_s.strip
      @scope = scope
      @request_context = request_context
      @subject = subject
      @expires_in = expires_in
    end

    def call
      validate_key!
      lock = acquire_lock!
      process_claimed_request
    ensure
      lock&.release
    end

    private

    def acquire_lock!
      lock = ClaimLock.new(scope: @scope, subject: @subject, key: @key)
      raise IdempotencyInProgressError unless lock.acquire

      lock
    end

    def process_claimed_request
      record, claim_state = claim_record
      return resolve_existing_result(record, claim_state) unless claim_state == :claimed

      execute_and_complete(record)
    rescue StandardError
      cleanup_processing_record(record) if record&.processing?
      raise
    end

    def claim_record
      record = IdempotencyKey.lock.find_by(lookup_attributes)
      return [create_processing_record, :claimed] unless record
      return [reclaim_expired_record(record), :claimed] if record.expired?
      return [record, :conflict] if record.request_fingerprint != request_fingerprint
      return [record, :completed] if record.completed?

      [record, :processing]
    end

    def create_processing_record = IdempotencyKey.create!(claim_attributes)

    def reclaim_expired_record(record)
      record.update!(claim_attributes.except(:idempotency_scope, :key_digest, :subject_type, :subject_id))
      record
    end

    def resolve_existing_result(record, state)
      raise IdempotencyInProgressError if state == :processing
      raise IdempotencyConflictError if state == :conflict

      replay_result(record)
    end

    def execute_and_complete(record)
      payload = @request_context.fetch(:operation).call
      record.with_lock do
        record.update!(
          status: IdempotencyKey::COMPLETED_STATUS,
          response_status: Rack::Utils.status_code(payload.fetch(:status, :ok)),
          response_payload: payload.deep_stringify_keys,
          completed_at: Time.current
        )
      end
      Result.new(payload:, replayed: false)
    end

    def replay_result(record) = Result.new(payload: ResponsePayload.load(record.response_payload), replayed: true)

    def cleanup_processing_record(record)
      record.with_lock do
        record.destroy! if record.processing?
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def validate_key!
      raise InvalidIdempotencyKeyError unless KEY_FORMAT.match?(@key)
    end

    def claim_attributes
      lookup_attributes.merge(
        request_fingerprint: request_fingerprint,
        request_method: @request_context.fetch(:method),
        request_path: @request_context.fetch(:path),
        status: IdempotencyKey::PROCESSING_STATUS,
        response_status: nil,
        response_payload: nil,
        completed_at: nil,
        expires_at: Time.current + @expires_in
      )
    end

    def lookup_attributes
      {
        idempotency_scope: @scope,
        key_digest: Digest::SHA256.hexdigest(@key),
        subject_type: @subject&.class&.name,
        subject_id: @subject&.id
      }
    end

    def request_fingerprint = @request_context.fetch(:fingerprint)
  end
end
