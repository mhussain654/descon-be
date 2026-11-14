# frozen_string_literal: true

require 'date'

module Admin
  module JobLogs
    # Reads and checks the Job logs filters (job class, status, enqueued date
    # range) and applies them to a Solid Queue job scope.
    class Filters
      STATUSES = %w[pending scheduled running finished failed].freeze
      ALLOWED = %w[job_class status enqueued_from enqueued_to].freeze

      attr_reader :values

      def initialize(raw, job_classes:)
        @job_classes = job_classes
        @values = parse(raw)
      end

      def apply(scope)
        values.reduce(scope) do |current, (name, value)|
          case name
          when 'job_class' then current.where(class_name: value)
          when 'status' then apply_status(current, value)
          when 'enqueued_from' then current.where(created_at: day(value).beginning_of_day..)
          else current.where(created_at: ..day(value).end_of_day)
          end
        end
      end

      private

      def parse(raw)
        return {} unless raw.respond_to?(:to_unsafe_h)

        values = raw.to_unsafe_h.compact_blank.transform_values(&:to_s)
        unsupported = values.keys - ALLOWED
        raise UnsupportedFilterError.new(filter_name: unsupported.first) if unsupported.any?

        validate_choice!(values, 'job_class', @job_classes)
        validate_choice!(values, 'status', STATUSES)
        validate_dates!(values)
        values
      end

      def validate_choice!(values, name, choices)
        return unless values.key?(name)
        return if choices.include?(values[name])

        raise InvalidQueryParameterError.new(field: "filter.#{name}")
      end

      def validate_dates!(values)
        from = values['enqueued_from'] && date_for(values['enqueued_from'], field: 'filter.enqueued_from')
        to = values['enqueued_to'] && date_for(values['enqueued_to'], field: 'filter.enqueued_to')
        raise InvalidQueryParameterError.new(field: 'filter.enqueued_to') if from && to && from > to
      end

      def apply_status(scope, status)
        return scope.where.not(finished_at: nil) if status == 'finished'

        unfinished = scope.where(finished_at: nil)
        case status
        when 'failed' then unfinished.where(id: ::SolidQueue::FailedExecution.select(:job_id))
        when 'running' then unfinished.where(id: ::SolidQueue::ClaimedExecution.select(:job_id))
        when 'scheduled' then unfinished.where(id: ::SolidQueue::ScheduledExecution.select(:job_id))
        else pending(unfinished)
        end
      end

      def pending(scope)
        scope.where.not(id: ::SolidQueue::FailedExecution.select(:job_id))
             .where.not(id: ::SolidQueue::ClaimedExecution.select(:job_id))
             .where.not(id: ::SolidQueue::ScheduledExecution.select(:job_id))
      end

      def day(value) = Date.iso8601(value).in_time_zone

      def date_for(value, field:)
        Date.iso8601(value)
      rescue Date::Error
        raise InvalidQueryParameterError.new(field:)
      end
    end
  end
end
