# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Pundit::Authorization

  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from BaseError, with: :render_api_error
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  private

  def render_success(data: {}, meta: {}, status: :ok)
    render json: {
      data: data,
      meta: meta.merge(request_id: request.request_id, timestamp: Time.current.iso8601),
      errors: []
    }, status: status
  end

  def render_api_error(error)
    render json: {
      errors: [
        {
          code: error.code,
          message: error.message,
          field: error.field
        }.compact
      ],
      request_id: request.request_id
    }, status: error.status
  end

  def render_record_invalid(error)
    invalid_record = error.record
    field = invalid_record.errors.attribute_names.first

    render_api_error(
      ValidationError.new(
        field: field,
        message: invalid_record.errors.full_messages.first || 'The request could not be processed.'
      )
    )
  end

  def render_not_found(error)
    render_api_error(NotFoundError.new(message: error.message))
  end

  def render_forbidden
    render_api_error(ForbiddenError.new)
  end
end
