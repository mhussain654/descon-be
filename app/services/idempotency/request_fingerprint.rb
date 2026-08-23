# frozen_string_literal: true

require 'digest'

module Idempotency
  class RequestFingerprint < ApplicationService
    def initialize(request:)
      @request = request
    end

    def call
      Digest::SHA256.hexdigest(
        [
          @request.request_method,
          @request.fullpath,
          @request.headers['Authorization'].to_s,
          @request.raw_post.to_s
        ].join("\n")
      )
    end
  end
end
