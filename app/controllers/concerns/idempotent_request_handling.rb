# frozen_string_literal: true

module IdempotentRequestHandling
  extend ActiveSupport::Concern

  private

  def render_idempotent_response
    key = request.headers['Idempotency-Key'].to_s.strip
    return render_payload(yield) if key.blank?

    stored_response = idempotency_response_store.read(key:)
    return replay_stored_response(stored_response) if stored_response

    payload = yield
    rendered_response = render_payload(payload)
    persist_idempotent_response(key:, payload:)
    rendered_response
  end

  def render_payload(payload)
    renderer_for(payload.fetch(:type)).call(payload)
  end

  def render_cached_response(payload)
    render_payload(payload.deep_symbolize_keys)
  end

  def success_payload(data:, status: :ok, meta: {})
    { type: :success, data:, status:, meta: meta.merge(timestamp:) }
  end

  def collection_payload(data:, pagination:, status: :ok, meta: {})
    { type: :collection, data:, pagination:, status:, meta: meta.merge(timestamp:) }
  end

  def renderer_for(payload_type)
    return method(:render_success_payload) if payload_type == :success
    return method(:render_collection_payload) if payload_type == :collection

    raise ArgumentError, "Unknown payload type: #{payload_type}"
  end

  def idempotency_response_store
    @idempotency_response_store ||= Idempotency::ResponseStore.new(cache: Rails.cache)
  end

  def replay_stored_response(stored_response)
    fingerprint = Idempotency::RequestFingerprint.call(request:)
    raise IdempotencyConflictError unless stored_response.fetch('fingerprint') == fingerprint

    response.set_header('Idempotency-Replayed', 'true')
    render_cached_response(stored_response.fetch('response'))
  end

  def persist_idempotent_response(key:, payload:)
    fingerprint = Idempotency::RequestFingerprint.call(request:)
    idempotency_response_store.write(key:, fingerprint:, response: payload)
  end

  def render_success_payload(payload)
    render_success(data: payload.fetch(:data), meta: payload.fetch(:meta, {}), status: payload.fetch(:status, :ok))
  end

  def render_collection_payload(payload)
    render_collection(
      data: payload.fetch(:data),
      pagination: payload.fetch(:pagination),
      meta: payload.fetch(:meta, {}),
      status: payload.fetch(:status, :ok)
    )
  end
end
