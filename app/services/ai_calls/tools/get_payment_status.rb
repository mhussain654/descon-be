# frozen_string_literal: true

module AiCalls
  module Tools
    class GetPaymentStatus < VerifiedDataTool
      private

      def data
        eligibility = ::Payments::EligibilityService.call(candidate:)
        ::Payments::EligibilitySerializer.new(eligibility).as_json
      end
    end
  end
end
