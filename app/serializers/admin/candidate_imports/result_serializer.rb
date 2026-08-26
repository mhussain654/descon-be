# frozen_string_literal: true

module Admin
  module CandidateImports
    class ResultSerializer
      def initialize(result)
        @result = result
      end

      def as_json(*)
        {
          successful_rows: @result.fetch(:successful_rows),
          failed_rows: @result.fetch(:failed_rows),
          skipped_rows: @result.fetch(:skipped_rows),
          total_rows: @result.fetch(:total_rows),
          errors: @result.fetch(:errors)
        }
      end
    end
  end
end
