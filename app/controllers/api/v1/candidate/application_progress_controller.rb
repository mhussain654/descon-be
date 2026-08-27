# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class ApplicationProgressController < ProtectedController
        def show
          authorize current_candidate, policy_class: ::Candidates::ApplicationProgressPolicy

          progress = ::Candidates::ApplicationProgress::SummaryService.call(candidate: current_candidate)
          render_success(data: ::Candidates::ApplicationProgressSerializer.new(progress).as_json)
        end
      end
    end
  end
end
