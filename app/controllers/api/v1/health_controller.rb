# frozen_string_literal: true

module Api
  module V1
    class HealthController < BaseController
      READINESS_DEPENDENCIES = {
        primary_database: ActiveRecord::Base,
        cache_database: SolidCache::Record,
        queue_database: SolidQueue::Record,
        cable_database: SolidCable::Record
      }.freeze

      def live
        render_success(data: { status: 'ok', message: t('api.messages.health.ok') })
      end

      def ready
        check_readiness_dependencies!
        render_success(data: { status: 'ready', message: t('api.messages.health.ready') })
      rescue ActiveRecord::ActiveRecordError
        render_api_error(service_unavailable_error)
      end

      private

      def check_readiness_dependencies!
        loaded_readiness_dependencies.each do |dependency_name, record_class|
          record_class.connection.execute('SELECT 1')
        rescue ActiveRecord::ActiveRecordError => e
          log_readiness_failure(dependency_name, e)
          raise
        end
      end

      def loaded_readiness_dependencies
        seen_connection_names = Set.new

        READINESS_DEPENDENCIES.each_with_object({}) do |(name, record_class), dependencies|
          db_config = record_class.connection_db_config
          next unless db_config
          next if seen_connection_names.include?(db_config.name)

          seen_connection_names << db_config.name
          dependencies[name] = record_class
        end
      end

      def log_readiness_failure(dependency_name, error)
        Rails.logger.error(
          event: 'readiness_check_failed',
          dependency: dependency_name,
          error_class: error.class.name,
          status: 'unavailable'
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
