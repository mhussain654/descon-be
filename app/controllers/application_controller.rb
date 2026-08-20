# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Pundit::Authorization
  include AbstractController::Translation

  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  rescue_from BaseError, with: :render_api_error
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  private

  def process_action(*)
    I18n.with_locale(resolved_locale) { super }
  end

  def resolved_locale
    Localization::LocaleResolver.call(
      explicit_locale: request.headers['X-Locale'],
      accept_language: request.headers['Accept-Language']
    )
  end

  def render_success(data: {}, meta: {}, status: :ok)
    response.set_header('Content-Language', I18n.locale.to_s)

    render json: {
      data: data,
      meta: meta.merge(request_id: request.request_id, timestamp: Time.current.iso8601),
      errors: []
    }, status: status
  end

  def render_api_error(error)
    response.set_header('Content-Language', I18n.locale.to_s)

    render json: {
      errors: [serialized_error(error)],
      request_id: request.request_id
    }, status: error.status
  end

  def render_record_invalid(error)
    invalid_record = error.record
    field = invalid_record.errors.attribute_names.first

    render_api_error(
      ValidationError.new(
        field: field,
        message: invalid_record.errors.full_messages.first || t('api.errors.validation_failed')
      )
    )
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

  def serialized_error(error)
    {
      code: error.code,
      message: error.message,
      field: error.field
    }.compact
  end
end
