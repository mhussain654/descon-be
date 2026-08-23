# frozen_string_literal: true

module ApiResponseHandling
  extend ActiveSupport::Concern

  private

  def render_success(data: {}, meta: {}, status: :ok)
    set_standard_response_headers

    render json: {
      data: data,
      meta: success_meta(meta),
      errors: []
    }, status: status
  end

  def render_collection(data:, pagination:, meta: {}, status: :ok)
    render_success(data:, meta: meta.merge(pagination:), status:)
  end

  def render_api_error(error)
    render_api_errors([error], status: error.status)
  end

  def render_api_errors(errors, status:)
    set_standard_response_headers

    render json: {
      errors: errors.map { |error| serialized_error(error) },
      request_id: request.request_id,
      timestamp: timestamp
    }, status:
  end

  def render_record_invalid(error)
    validation_errors = error.record.errors.map do |record_error|
      ValidationError.new(
        field: record_error.attribute == :base ? nil : record_error.attribute,
        message: record_error.full_message
      )
    end

    render_api_errors(validation_errors.presence || [ValidationError.new], status: :unprocessable_entity)
  end

  def render_parameter_missing(error)
    render_api_error(
      BadRequestError.new(
        field: error.param,
        message: t('api.errors.parameter_missing')
      )
    )
  end

  def render_not_found(_error)
    render_api_error(NotFoundError.new)
  end

  def render_forbidden
    render_api_error(ForbiddenError.new)
  end

  def render_unexpected_error(error)
    Rails.logger.error(unexpected_error_payload(error).to_json)
    render_api_error(InternalServerError.new)
  end

  def serialized_error(error)
    {
      code: error.code,
      message: error.message,
      field: error.field
    }.compact
  end

  def set_standard_response_headers
    response.set_header('Content-Language', I18n.locale.to_s)
    response.set_header('Vary', 'Accept-Language, X-Locale')
    response.set_header('X-Request-Id', request.request_id)
  end

  def success_meta(meta)
    meta.merge(request_id: request.request_id, timestamp: meta[:timestamp] || timestamp)
  end

  def unexpected_error_payload(error)
    {
      event: 'unexpected_error',
      request_id: request.request_id,
      controller: self.class.name,
      action: action_name,
      error_class: error.class.name,
      error_message: error.message
    }
  end

  def timestamp
    Time.current.utc.iso8601
  end
end
