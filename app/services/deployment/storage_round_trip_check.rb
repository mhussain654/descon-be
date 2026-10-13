# frozen_string_literal: true

require 'net/http'
require 'securerandom'

module Deployment
  # Proves private object storage works end to end through the application's
  # own Active Storage service: upload, authorized read, time-limited signed
  # URL, refusal of the same object without its signature, delete. It writes
  # one tiny throwaway object and removes it, so it is an explicit operator
  # action (`bin/rails deployment:storage_round_trip`), never part of a
  # routine deploy. It never touches a real candidate document.
  class StorageRoundTripCheck < ApplicationService
    URL_TTL = 60.seconds
    HTTP_TIMEOUT_SECONDS = 10
    REFUSED_STATUS_CODES = %w[401 403].freeze

    # `fetch` is the HTTP GET used to prove the signed and unsigned URL
    # behavior; it is injectable only so specs need no network.
    def initialize(service: ActiveStorage::Blob.service, fetch: method(:http_get))
      @service = service
      @fetch = fetch
    end

    def call
      return [failure('storage service', 'a private S3 service is required (got local disk)')] unless s3?

      run(key: "deployment-check/#{SecureRandom.uuid}",
          payload: "descon deployment storage check #{SecureRandom.hex(8)}")
    rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
      [failure('storage round trip', "S3 error (#{e.class.name})")]
    end

    private

    def s3? = @service.respond_to?(:bucket)

    # The throwaway object is always removed, whatever else happened.
    def run(key:, payload:)
      results = []
      begin
        results.concat(upload_and_read_back(key, payload))
        results.concat(signed_and_unsigned_access(key, payload)) if results.none?(&:failed?)
      ensure
        results << delete_result(key)
      end
      results
    end

    def upload_and_read_back(key, payload)
      @service.upload(key, StringIO.new(payload), checksum: Digest::MD5.base64digest(payload))
      return [failure('upload/read-back', 'downloaded bytes differ from the uploaded bytes')] unless
        @service.download(key) == payload

      [pass('upload/read-back', "wrote and read #{payload.bytesize} bytes in #{@service.bucket.name}")]
    end

    def signed_and_unsigned_access(key, payload)
      signed = signed_url(key)
      [signed_access_result(signed, payload), unsigned_access_result(signed)]
    end

    def signed_url(key)
      @service.url(key, expires_in: URL_TTL, filename: ActiveStorage::Filename.new('check.txt'),
                        content_type: 'text/plain', disposition: 'attachment')
    end

    def signed_access_result(signed, payload)
      response = @fetch.call(signed)
      return pass('signed URL', "time-limited URL (#{URL_TTL.to_i}s) served the object") if
        response.code == '200' && response.body == payload

      failure('signed URL', "expected 200 with the object, got HTTP #{response.code}")
    end

    # The same object with no signature must be refused: that is what makes
    # the bucket private rather than merely unlisted.
    def unsigned_access_result(signed)
      response = @fetch.call(signed.split('?').first)
      if REFUSED_STATUS_CODES.include?(response.code)
        return pass('private bucket', "unsigned request refused (HTTP #{response.code})")
      end

      failure('private bucket', "unsigned request returned HTTP #{response.code}; the object is not private")
    end

    def delete_result(key)
      @service.delete(key)
      return failure('delete', 'object still exists after delete') if @service.exist?(key)

      pass('delete', 'throwaway object removed')
    end

    def http_get(url)
      uri = URI.parse(url)
      options = { use_ssl: uri.scheme == 'https', open_timeout: HTTP_TIMEOUT_SECONDS,
                  read_timeout: HTTP_TIMEOUT_SECONDS }
      Net::HTTP.start(uri.host, uri.port, **options) { |http| http.get(uri.request_uri) }
    end

    def pass(name, detail) = CheckResult.new(name:, status: :pass, detail:)
    def failure(name, detail) = CheckResult.new(name:, status: :fail, detail:)
  end
end
