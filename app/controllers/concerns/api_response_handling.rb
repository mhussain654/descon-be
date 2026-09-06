# frozen_string_literal: true

# Shared helpers for rendering the app's standard JSON success/error envelope and
# translating common Rails/Pundit exceptions into consistent API error responses.
module ApiResponseHandling
  extend ActiveSupport::Concern

  private

  # Renders a successful JSON response with the standard data/meta/errors envelope.
  def render_success(data: {}, meta: {}, status: :ok)
    set_standard_response_headers

    render json: {
      data: data,
      meta: success_meta(meta),
      errors: []
    }, status: status
  end

  # Renders a successful paginated collection response by folding pagination info into the meta block.
  def render_collection(data:, pagination:, meta: {}, status: :ok)
    render_success(data:, meta: meta.merge(pagination:), status:)
  end

  # Renders a single API error using that error's own HTTP status.
  def render_api_error(error)
    render_api_errors([error], status: error.status)
  end

  # Renders one or more API errors as JSON with the given HTTP status, request id, and timestamp.
  def render_api_errors(errors, status:)
    set_standard_response_headers

    render json: {
      errors: errors.map { |error| serialized_error(error) },
      request_id: request.request_id,
      timestamp: timestamp
    }, status:
  end

  # Converts ActiveRecord validation failures into the app's ValidationError format and renders them as 422.
  def render_record_invalid(error)
    validation_errors = error.record.errors.map do |record_error|
      ValidationError.new(
        field: record_error.attribute == :base ? nil : record_error.attribute,
        message: record_error.full_message
      )
    end

    render_api_errors(validation_errors.presence || [ValidationError.new], status: :unprocessable_content)
  end

  # Renders a 400 response when a required request parameter is missing.
  def render_parameter_missing(error)
    render_api_error(
      BadRequestError.new(
        field: error.param,
        message: t('api.errors.parameter_missing')
      )
    )
  end

  # Renders a generic 404 response for any ActiveRecord::RecordNotFound.
  def render_not_found(_error)
    render_api_error(NotFoundError.new)
  end

  # Renders a generic 403 response for Pundit authorization failures.
  def render_forbidden
    render_api_error(ForbiddenError.new)
  end

  # Logs unexpected errors and renders a generic 500 response, re-raising Pundit verification
  # errors (missing authorize/policy_scope calls) instead of masking them.
  def render_unexpected_error(error)
    raise error if pundit_verification_error?(error)

    Rails.logger.error(unexpected_error_payload(error).to_json)
    render_api_error(InternalServerError.new)
  end

  # Builds the public JSON representation of a single error object.
  def serialized_error(error)
    {
      code: error.code,
      details: error.details,
      message: error.message,
      field: error.field
    }.compact
  end

  # Sets the response headers common to every API response (locale, vary, request id).
  def set_standard_response_headers
    response.set_header('Content-Language', I18n.locale.to_s)
    response.set_header('Vary', 'Accept-Language, X-Locale')
    response.set_header('X-Request-Id', request.request_id)
  end

  # Merges request id and timestamp into the caller-supplied meta hash for a success response.
  def success_meta(meta)
    meta.merge(request_id: request.request_id, timestamp: meta[:timestamp] || timestamp)
  end

  # Builds the structured payload logged for an unexpected (unhandled) error.
  def unexpected_error_payload(error)
    {
      event: 'unexpected_error',
      request_id: request.request_id,
      controller: self.class.name,
      action: action_name,
      error_class: error.class.name
    }
  end

  # Returns the current UTC time formatted as ISO8601 for response payloads.
  def timestamp
    Time.current.utc.iso8601
  end

  # Detects the Pundit "developer forgot to call authorize/policy_scope" errors so they
  # aren't swallowed and reported as generic server errors.
  def pundit_verification_error?(error)
    error.is_a?(Pundit::AuthorizationNotPerformedError) || error.is_a?(Pundit::PolicyScopingNotPerformedError)
  end
end
