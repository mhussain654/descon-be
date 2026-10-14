# frozen_string_literal: true

module Deployment
  # Read-only readiness report for a deployed environment, run by
  # `bin/rails deployment:preflight` (and by Capistrano before a new release is
  # switched live). It changes no data and prints no secret. It answers, for a
  # first AWS deployment: can every database be reached over verified TLS and
  # is pg_dump compatible (DatabaseReadinessCheck), is object storage private
  # S3 reached through the instance role, are the credentials the enabled
  # integrations need present, and what does the malware-scanner mode mean for
  # uploads.
  #
  # Usage: Deployment::PreflightCheck.call -> [Deployment::CheckResult]
  class PreflightCheck < ApplicationService
    STORAGE_SENTINEL_KEY = 'deployment-preflight/does-not-exist'

    def call
      [*DatabaseReadinessCheck.call, storage_result, credentials_result, scanner_result]
    end

    private

    def storage_result
      service = ActiveStorage::Blob.service
      return disk_storage_result unless service.respond_to?(:bucket)

      service.exist?(STORAGE_SENTINEL_KEY)
      s3_storage_result(service.bucket)
    rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
      CheckResult.new(name: 'storage', status: :fail, detail: "S3 unreachable (#{e.class.name})")
    rescue StandardError => e
      # Diagnostic boundary: a misconfigured service (for example an option
      # the S3 client rejects) must be reported as a failed check, not abort
      # the report. Only the class name is shown.
      CheckResult.new(name: 'storage', status: :fail, detail: "storage service could not be built (#{e.class.name})")
    end

    def s3_storage_result(bucket)
      detail = "S3 bucket #{bucket.name} (#{bucket.client.config.region}) reachable"
      unless static_aws_keys?
        return CheckResult.new(name: 'storage', status: :pass,
                               detail: "#{detail}; credentials from the default chain")
      end

      CheckResult.new(name: 'storage', status: :warn,
                      detail: "#{detail}; static AWS access keys are set -- use the EC2 instance role instead")
    end

    def disk_storage_result
      CheckResult.new(name: 'storage', status: Rails.env.production? ? :fail : :pass,
                      detail: 'local disk storage; production must use a private S3 service')
    end

    def static_aws_keys?
      ENV['AWS_ACCESS_KEY_ID'].present? || ENV['AWS_SECRET_ACCESS_KEY'].present?
    end

    def credentials_result
      missing = missing_required_credentials
      return CheckResult.new(name: 'credentials', status: :pass, detail: credentials_detail) if missing.empty?

      CheckResult.new(name: 'credentials', status: :fail,
                      detail: "missing from encrypted credentials: #{missing.join(', ')}")
    end

    def missing_required_credentials
      missing = []
      missing << "sendpk.#{Rails.env}.api_key" if sms_provider == 'sendpk' && !credential?(:sendpk, :api_key)
      missing << "kuickpay.#{Rails.env}.secured_key" if kuickpay_enabled? && !credential?(:kuickpay, :secured_key)
      missing
    end

    def credentials_detail
      "send.pk api_key present=#{credential?(:sendpk, :api_key)} (SMS_PROVIDER=#{sms_provider}); " \
        "KuickPay secured_key present=#{credential?(:kuickpay, :secured_key)} (enabled=#{kuickpay_enabled?})"
    end

    def credential?(integration, key)
      Rails.application.credentials.dig(integration, Rails.env.to_sym, key).present?
    end

    def sms_provider = ENV.fetch('SMS_PROVIDER', 'test')

    def kuickpay_enabled? = Payments::Configuration.new.kuickpay_enabled?

    def scanner_result
      configuration = MalwareScanning::Configuration.new
      return scanner_check(:fail, 'mock scanner on a live deployment (the application will not boot)') if
        configuration.prohibited_mock?
      return scanner_check(:warn, mock_scanner_detail(configuration)) if configuration.mock?
      return scanner_check(:pass, "provider #{configuration.scanner_code}") if configuration.provider

      scanner_check(:warn, 'no scanner configured: candidate document uploads are refused')
    end

    def mock_scanner_detail(configuration)
      "MOCK scanner active (APP_ENV=#{configuration.deployment_environment}): uploads are NOT scanned " \
        'for malware -- do not use real candidate documents'
    end

    def scanner_check(status, detail) = CheckResult.new(name: 'malware scanner', status:, detail:)
  end
end
