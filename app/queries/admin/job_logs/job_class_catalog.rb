# frozen_string_literal: true

module Admin
  module JobLogs
    # Every job class a developer can pick on the Job logs page: each job under
    # app/jobs (whether or not it has run yet), plus any other class name
    # Solid Queue has recorded (e.g. Action Mailer delivery jobs).
    class JobClassCatalog
      JOBS_ROOT = Rails.root.join('app/jobs')
      EXCLUDED = %w[ApplicationJob].freeze

      def self.call = new.call

      def call
        (application_job_classes + recorded_job_classes).uniq.sort - EXCLUDED
      end

      private

      def application_job_classes
        JOBS_ROOT.glob('**/*_job.rb').map do |path|
          path.relative_path_from(JOBS_ROOT).to_s.delete_suffix('.rb').camelize
        end
      end

      def recorded_job_classes
        ::SolidQueue::Job.distinct.pluck(:class_name)
      end
    end
  end
end
