# frozen_string_literal: true

require 'rails_helper'
require 'active_storage/service/disk_service' # autoloaded lazily; spec order must not matter

RSpec.describe Deployment::StorageRoundTripCheck do
  # A minimal in-memory stand-in for ActiveStorage's S3 service: it records
  # what was uploaded and answers the same methods the check calls.
  let(:store) { {} }
  let(:service) do
    store_ref = store
    Class.new do
      define_method(:bucket) { Struct.new(:name).new('descon-mps-documents') }
      define_method(:upload) { |key, io, **| store_ref[key] = io.read }
      define_method(:download) { |key| store_ref.fetch(key) }
      define_method(:exist?) { |key| store_ref.key?(key) }
      define_method(:delete) { |key| store_ref.delete(key) }
      define_method(:url) do |key, **|
        "https://descon-mps-documents.s3.ap-southeast-1.amazonaws.com/#{key}?X-Amz-Signature=abc"
      end
    end.new
  end

  def results_named(results, name) = results.find { |result| result.name == name }

  # Answers the signed URL (query string present) with the stored object and
  # the unsigned URL with `unsigned_status`.
  def fetcher(unsigned_status:, signed_status: 200)
    response = Struct.new(:code, :body)
    lambda do |url|
      if url.include?('?')
        response.new(signed_status.to_s, signed_status == 200 ? store.values.first.to_s : '')
      else
        response.new(unsigned_status.to_s, '')
      end
    end
  end

  describe '.call' do
    context 'when the bucket is private and the signed URL works' do
      it 'passes every step and removes the throwaway object' do
        results = described_class.call(service:, fetch: fetcher(unsigned_status: 403))

        expect(results.map(&:status)).to all(eq(:pass))
        expect(results.map(&:name)).to eq(['upload/read-back', 'signed URL', 'private bucket', 'delete'])
        expect(store).to be_empty
      end
    end

    context 'when the unsigned object is publicly readable' do
      it 'fails the private-bucket step but still deletes the object' do
        results = described_class.call(service:, fetch: fetcher(unsigned_status: 200))

        expect(results_named(results, 'private bucket')).to be_failed
        expect(results_named(results, 'private bucket').detail).to include('not private')
        expect(store).to be_empty
      end
    end

    context 'when the signed URL does not serve the object' do
      it 'fails the signed-URL step' do
        results = described_class.call(service:, fetch: fetcher(unsigned_status: 403, signed_status: 403))

        expect(results_named(results, 'signed URL')).to be_failed
      end
    end

    context 'when the bytes read back differ from the bytes written' do
      it 'fails the upload step, skips URL checks and cleans up' do
        allow(service).to receive(:download).and_return('corrupted')

        results = described_class.call(service:)

        expect(results_named(results, 'upload/read-back')).to be_failed
        expect(results.map(&:name)).to eq(%w[upload/read-back delete])
        expect(store).to be_empty
      end
    end

    context 'when the object cannot be deleted' do
      it 'fails the delete step' do
        allow(service).to receive(:delete)

        results = described_class.call(service:, fetch: fetcher(unsigned_status: 403))

        expect(results_named(results, 'delete')).to be_failed
      end
    end

    context 'when S3 raises' do
      it 'reports a single failure naming the error class only' do
        allow(service).to receive(:upload).and_raise(Aws::S3::Errors::AccessDenied.new(nil, 'secret detail'))

        results = described_class.call(service:)

        expect(results.size).to eq(1)
        expect(results.first).to be_failed
        expect(results.first.detail).to include('Aws::S3::Errors::AccessDenied')
        expect(results.first.detail).not_to include('secret detail')
      end
    end

    context 'when the storage service is local disk' do
      it 'refuses to run' do
        disk = ActiveStorage::Service::DiskService.new(root: Dir.tmpdir)

        results = described_class.call(service: disk)

        expect(results.size).to eq(1)
        expect(results.first).to be_failed
        expect(results.first.detail).to include('private S3 service is required')
      end
    end
  end
end
