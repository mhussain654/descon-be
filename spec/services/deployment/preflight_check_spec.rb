# frozen_string_literal: true

require 'rails_helper'
require 'active_storage/service/disk_service' # autoloaded lazily; spec order must not matter

RSpec.describe Deployment::PreflightCheck do
  def result_named(results, name) = results.find { |result| result.name == name }

  let(:production) { ActiveSupport::EnvironmentInquirer.new('production') }
  let(:disk_service) { ActiveStorage::Service::DiskService.new(root: Dir.tmpdir) }

  before do
    allow(Deployment::DatabaseReadinessCheck).to receive(:call).and_return([])
  end

  describe '.call' do
    it 'includes the database readiness results' do
      database_result = Deployment::CheckResult.new(name: 'primary database', status: :pass, detail: 'ok')
      allow(Deployment::DatabaseReadinessCheck).to receive(:call).and_return([database_result])

      expect(described_class.call).to include(database_result)
    end
  end

  describe 'storage' do
    let(:s3_service) do
      client = double('client', config: double('config', region: 'ap-southeast-1')) # rubocop:disable RSpec/VerifiedDoubles
      double('s3 service', bucket: double('bucket', name: 'descon-mps-documents', client:), # rubocop:disable RSpec/VerifiedDoubles
                           exist?: false)
    end

    it 'passes for a reachable S3 bucket using the default credential chain' do
      allow(ActiveStorage::Blob).to receive(:service).and_return(s3_service)

      result = result_named(described_class.call, 'storage')

      expect(result.status).to eq(:pass)
      expect(result.detail).to include('descon-mps-documents', 'ap-southeast-1', 'default chain')
    end

    it 'warns when static AWS keys are configured instead of the instance role' do
      allow(ActiveStorage::Blob).to receive(:service).and_return(s3_service)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AWS_ACCESS_KEY_ID').and_return('AKIAEXAMPLE')

      result = result_named(described_class.call, 'storage')

      expect(result.status).to eq(:warn)
      expect(result.detail).to include('instance role')
      expect(result.detail).not_to include('AKIAEXAMPLE')
    end

    it 'fails when S3 refuses the request' do
      allow(s3_service).to receive(:exist?).and_raise(Aws::S3::Errors::AccessDenied.new(nil, 'denied'))
      allow(ActiveStorage::Blob).to receive(:service).and_return(s3_service)

      result = result_named(described_class.call, 'storage')

      expect(result).to be_failed
      expect(result.detail).to include('Aws::S3::Errors::AccessDenied')
    end

    it 'reports a storage service that cannot be built instead of aborting the report' do
      allow(ActiveStorage::Blob).to receive(:service).and_raise(ArgumentError, 'invalid configuration option')

      result = result_named(described_class.call, 'storage')

      expect(result).to be_failed
      expect(result.detail).to include('could not be built (ArgumentError)')
      expect(result.detail).not_to include('invalid configuration option')
    end

    it 'fails on local disk in production' do
      allow(Rails).to receive(:env).and_return(production)
      allow(ActiveStorage::Blob).to receive(:service).and_return(disk_service)

      expect(result_named(described_class.call, 'storage')).to be_failed
    end

    it 'accepts local disk outside production' do
      allow(ActiveStorage::Blob).to receive(:service).and_return(disk_service)

      expect(result_named(described_class.call, 'storage').status).to eq(:pass)
    end
  end

  describe 'credentials' do
    # A developer's .env (loaded by dotenv in test) may enable send.pk or
    # KuickPay; these examples must not depend on it.
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SMS_PROVIDER', 'test').and_return('test')
      allow(Payments::Configuration).to receive(:new)
        .and_return(instance_double(Payments::Configuration, kuickpay_enabled?: false))
    end

    it 'passes when nothing that needs a secret is enabled' do
      result = result_named(described_class.call, 'credentials')

      expect(result.status).to eq(:pass)
      expect(result.detail).to include('SMS_PROVIDER=test', 'enabled=false')
    end

    it 'fails when send.pk is selected but its production api key is missing' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SMS_PROVIDER', 'test').and_return('sendpk')
      allow(Rails.application.credentials).to receive(:config).and_return({ readable: true })

      result = result_named(described_class.call, 'credentials')

      expect(result).to be_failed
      expect(result.detail).to include('sendpk.test.api_key', 'the file decrypts')
    end

    it 'says the credentials could not be decrypted when the file reads as empty' do
      allow(Payments::Configuration).to receive(:new)
        .and_return(instance_double(Payments::Configuration, kuickpay_enabled?: true))
      allow(Rails.application.credentials).to receive(:config).and_return({})

      result = result_named(described_class.call, 'credentials')

      expect(result).to be_failed
      expect(result.detail).to include('could not be decrypted', 'RAILS_MASTER_KEY', 'kuickpay.test.secured_key')
    end

    it 'fails when KuickPay is enabled but its secured key is missing' do
      allow(Payments::Configuration).to receive(:new).and_return(instance_double(Payments::Configuration,
                                                                                 kuickpay_enabled?: true))
      allow(Rails.application.credentials).to receive(:config).and_return({ readable: true })

      result = result_named(described_class.call, 'credentials')

      expect(result).to be_failed
      expect(result.detail).to include('kuickpay.test.secured_key', 'the file decrypts')
    end

    it 'passes and never prints the secret when both are present' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SMS_PROVIDER', 'test').and_return('sendpk')
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:sendpk, :test, :api_key).and_return('super-secret')

      result = result_named(described_class.call, 'credentials')

      expect(result.status).to eq(:pass)
      expect(result.detail).to include('send.pk api_key present=true')
      expect(result.detail).not_to include('super-secret')
    end
  end

  describe 'malware scanner' do
    def stub_scanner(**attributes)
      defaults = { prohibited_mock?: false, mock?: false, provider: nil, scanner_code: nil,
                   deployment_environment: 'staging' }
      allow(MalwareScanning::Configuration).to receive(:new)
        .and_return(instance_double(MalwareScanning::Configuration, defaults.merge(attributes)))
    end

    it 'warns loudly that a mock scanner leaves uploads unscanned' do
      stub_scanner(mock?: true, scanner_code: 'mock')

      result = result_named(described_class.call, 'malware scanner')

      expect(result.status).to eq(:warn)
      expect(result.detail).to include('MOCK scanner', 'NOT scanned', 'APP_ENV=staging')
    end

    it 'fails a mock scanner on a live deployment' do
      stub_scanner(prohibited_mock?: true, mock?: true, deployment_environment: 'production')

      expect(result_named(described_class.call, 'malware scanner')).to be_failed
    end

    it 'warns that uploads are refused when no scanner is configured' do
      stub_scanner

      result = result_named(described_class.call, 'malware scanner')

      expect(result.status).to eq(:warn)
      expect(result.detail).to include('uploads are refused')
    end

    it 'passes when a real provider is configured' do
      stub_scanner(provider: Object.new, scanner_code: 'clamav')

      result = result_named(described_class.call, 'malware scanner')

      expect(result.status).to eq(:pass)
      expect(result.detail).to eq('provider clamav')
    end
  end
end
