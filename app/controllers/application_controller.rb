# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Pundit::Authorization
  include AbstractController::Translation
  include ApiResponseHandling
  include IdempotentRequestHandling

  rescue_from StandardError, with: :render_unexpected_error
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  rescue_from BaseError, with: :render_api_error
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  private

  def process_action(*)
    I18n.with_locale(resolved_locale) { super }
  end

  def set_private_state_headers(updated_at:, etag_key:)
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('ETag', %("#{Digest::SHA256.hexdigest("#{etag_key}:#{updated_at&.to_i || 'none'}")}"))
  end

  def resolved_locale
    Localization::LocaleResolver.call(
      explicit_locale: request.headers['X-Locale'],
      accept_language: request.headers['Accept-Language']
    )
  end
end
