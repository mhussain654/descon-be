# frozen_string_literal: true

require 'digest'

module Candidates
  module DocumentSubmissions
    class SubmissionFingerprint < ApplicationService
      def initialize(request:)
        @request = request
      end

      def call
        Digest::SHA256.hexdigest([
          @request.request_method,
          @request.path
        ].join("\n"))
      end
    end
  end
end
