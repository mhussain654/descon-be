# frozen_string_literal: true

require 'rails_helper'

# config/storage.yml's `amazon` service has to build: it is the only place a
# bad option surfaces, and only in production (development and test use the
# disk service), so a mistake there goes unnoticed until the first deploy.
RSpec.describe 'config/storage.yml amazon service' do
  def service_configurations
    ActiveSupport::ConfigurationFile.parse(Rails.root.join('config/storage.yml')).deep_symbolize_keys
  end

  def build_service
    ActiveStorage::Service.configure(:amazon, service_configurations)
  end

  around do |example|
    keys = %w[AWS_S3_BUCKET AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY]
    original = ENV.values_at(*keys)
    keys.each { |key| ENV.delete(key) }
    ENV['AWS_REGION'] = 'ap-southeast-1'
    ENV['AWS_S3_BUCKET'] = 'descon-mps-documents-s3-bucket'
    # Building the client resolves credentials; give it fixed ones so the spec
    # never probes the EC2 metadata endpoint.
    original_credentials = Aws.config[:credentials]
    Aws.config[:credentials] = Aws::Credentials.new('test-key', 'test-secret')
    example.run
  ensure
    Aws.config[:credentials] = original_credentials
    keys.zip(original).each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it 'builds an S3 service without an invalid client option' do
    service = build_service

    expect(service).to be_a(ActiveStorage::Service::S3Service)
    expect(service.bucket.name).to eq('descon-mps-documents-s3-bucket')
  end

  it 'sends no per-request encryption options (the bucket default applies)' do
    expect(build_service.upload_options).not_to include(:server_side_encryption)
  end

  it 'uses the default credential chain when no static keys are set' do
    expect(service_configurations.dig(:amazon, :access_key_id)).to be_blank
    expect(service_configurations.dig(:amazon, :secret_access_key)).to be_blank
  end
end
