# frozen_string_literal: true

module IdempotentRequestHandling
  extend ActiveSupport::Concern

  private

  def render_idempotent_response(
    scope:,
    subject: nil,
    expires_in: Idempotency::RequestHandler::DEFAULT_EXPIRY,
    &operation
  )
    key = request.headers['Idempotency-Key'].to_s.strip
    return render_payload(yield) if key.blank?

    result = idempotency_result(key:, scope:, subject:, expires_in:, &operation)
    response.set_header('Idempotency-Replayed', 'true') if result.replayed
    render_payload(result.payload)
  end

  def render_payload(payload)
    renderer_for(payload.fetch(:type)).call(payload)
  end

  def render_cached_response(payload)
    render_payload(payload.deep_symbolize_keys)
  end

  def success_payload(data:, status: :ok, meta: {})
    { type: :success, data:, status:, meta: meta.merge(request_id: request.request_id, timestamp:) }
  end

  def collection_payload(data:, pagination:, status: :ok, meta: {})
    { type: :collection, data:, pagination:, status:, meta: meta.merge(request_id: request.request_id, timestamp:) }
  end

  def renderer_for(payload_type)
    return method(:render_success_payload) if payload_type == :success
    return method(:render_collection_payload) if payload_type == :collection

    raise ArgumentError, "Unknown payload type: #{payload_type}"
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

  def idempotency_result(key:, scope:, subject:, expires_in:, &operation)
    Idempotency::RequestHandler.call(
      key:,
      scope:,
      subject:,
      request_context: idempotency_request_metadata(operation),
      expires_in:
    )
  end

  def idempotency_request_metadata(operation)
    {
      method: request.request_method,
      path: request.path,
      fingerprint: Idempotency::RequestFingerprint.call(request:),
      operation:
    }
  end
end
