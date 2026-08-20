# frozen_string_literal: true

module Api
  module V1
    class HealthController < BaseController
      def live
        render_success(data: { status: 'ok' })
      end

      def ready
        ActiveRecord::Base.connection.execute('SELECT 1')
        render_success(data: { status: 'ready' })
      rescue ActiveRecord::ActiveRecordError => e
        render_api_error(
          BaseError.new(code: 'service_unavailable', message: e.message, status: :service_unavailable)
        )
      end
    end
  end
end
