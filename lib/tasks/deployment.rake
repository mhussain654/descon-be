# frozen_string_literal: true

# Operator-facing deployment checks (see docs/deployment/aws-ec2-runbook.md).
# Each prints one line per check, never a credential value, and exits
# non-zero if any check failed.
namespace :deployment do
  desc 'Read-only readiness report: four databases over verified TLS, pg_dump version, ' \
       'private S3 storage, credentials presence and malware-scanner mode.'
  task preflight: :environment do
    report_deployment_results(Deployment::PreflightCheck.call)
  end

  desc 'Solid Queue processes alive right now (run after a release is live).'
  task queue_status: :environment do
    report_deployment_results([Deployment::QueueStatusCheck.call])
  end

  desc 'Upload, read, sign, refuse-unsigned and delete one throwaway object through ' \
       'the application\'s storage service.'
  task storage_round_trip: :environment do
    report_deployment_results(Deployment::StorageRoundTripCheck.call)
  end
end

def report_deployment_results(results)
  results.each { |result| puts result }
  $stdout.flush
  abort('Deployment check FAILED.') if results.any?(&:failed?)

  puts 'Deployment check passed.'
end
