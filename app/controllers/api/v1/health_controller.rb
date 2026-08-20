# frozen_string_literal: true

module Api
  module V1
    class HealthController < BaseController
      def live
        render_success(data: { status: t('api.messages.health.ok') })
      end

      def ready
        ActiveRecord::Base.connection.execute('SELECT 1')
        render_success(data: { status: t('api.messages.health.ready') })
      rescue ActiveRecord::ActiveRecordError => e
        log_readiness_failure(e)
        render_api_error(service_unavailable_error)
      end

      private

      def log_readiness_failure(error)
        Rails.logger.error(
          event: 'readiness_check_failed',
          error_class: error.class.name,
          message: error.message
        )
      end

      def service_unavailable_error
        BaseError.new(
          code: 'service_unavailable',
          message: t('api.errors.service_unavailable'),
          status: :service_unavailable
        )
      end
    end
  end
end
