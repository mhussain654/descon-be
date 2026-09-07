# frozen_string_literal: true

# Shared helpers that let write actions (e.g. document upload, payment checkout) safely replay
# a request made with the same Idempotency-Key instead of repeating its side effects.
module IdempotentRequestHandling
  extend ActiveSupport::Concern

  private

  # Runs the given block under idempotency protection when an Idempotency-Key header is present
  # (or raises if one is required but missing), then renders either the fresh or replayed result.
  def render_idempotent_response(
    scope:,
    subject: nil,
    expires_in: Idempotency::RequestHandler::DEFAULT_EXPIRY,
    fingerprint: nil,
    required: false,
    &operation
  )
    key = request.headers['Idempotency-Key'].to_s.strip
    raise MissingIdempotencyKeyError if required && key.blank?
    return render_payload(yield) if key.blank?

    result = idempotency_result(key:, scope:, subject:, expires_in:, fingerprint:, &operation)
    response.set_header('Idempotency-Replayed', 'true') if result.replayed
    render_payload(result.payload)
  end

  # Dispatches a success/collection payload hash to the renderer matching its declared type.
  def render_payload(payload)
    renderer_for(payload.fetch(:type)).call(payload)
  end

  # Renders a payload that was previously stored (and retrieved with string keys) as a cached idempotent result.
  def render_cached_response(payload)
    render_payload(payload.deep_symbolize_keys)
  end

  # Builds a payload hash describing a single-resource success response, for use with idempotency handling.
  def success_payload(data:, status: :ok, meta: {})
    { type: :success, data:, status:, meta: meta.merge(request_id: request.request_id, timestamp:) }
  end

  # Builds a payload hash describing a paginated collection response, for use with idempotency handling.
  def collection_payload(data:, pagination:, status: :ok, meta: {})
    { type: :collection, data:, pagination:, status:, meta: meta.merge(request_id: request.request_id, timestamp:) }
  end

  # Looks up the render method for a given payload type, raising if the type is unrecognized.
  def renderer_for(payload_type)
    return method(:render_success_payload) if payload_type == :success
    return method(:render_collection_payload) if payload_type == :collection

    raise ArgumentError, "Unknown payload type: #{payload_type}"
  end

  # Renders a :success-type payload via the standard success envelope.
  def render_success_payload(payload)
    render_success(data: payload.fetch(:data), meta: payload.fetch(:meta, {}), status: payload.fetch(:status, :ok))
  end

  # Renders a :collection-type payload via the standard paginated collection envelope.
  def render_collection_payload(payload)
    render_collection(
      data: payload.fetch(:data),
      pagination: payload.fetch(:pagination),
      meta: payload.fetch(:meta, {}),
      status: payload.fetch(:status, :ok)
    )
  end

  # Delegates to the idempotency handler, which either executes the operation and stores its
  # result under the given key, or returns the previously stored result if the key was already used.
  def idempotency_result(key:, scope:, subject:, expires_in:, fingerprint:, &operation)
    Idempotency::RequestHandler.call(
      key:,
      scope:,
      subject:,
      request_context: idempotency_request_metadata(operation, fingerprint:),
      expires_in:
    )
  end

  # Builds the request metadata (method, path, fingerprint) stored alongside an idempotency key,
  # used to detect a key being replayed against a different request.
  def idempotency_request_metadata(operation, fingerprint:)
    {
      method: request.request_method,
      path: request.path,
      fingerprint: fingerprint || Idempotency::RequestFingerprint.call(request:),
      operation:
    }
  end
end
