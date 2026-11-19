# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate upload (or replace) a photo of their own boarding pass
      # once their flight is recorded. Always acts on the authenticated
      # candidate -- there is no id in the route.
      class FlightDetailBoardingPassesController < ProtectedController
        def update
          authorize current_candidate, :upload_boarding_pass?, policy_class: ::Candidates::WorkflowPolicy

          detail = ::CandidateWorkflows::FlightDetails::BoardingPassUploadService.call(
            candidate: current_candidate,
            uploaded_file: params.dig(:boarding_pass, :photo),
            request_id: request.request_id
          )
          response.set_header('Cache-Control', 'private, no-store')
          render_success(data: ::CandidateWorkflows::FlightDetailSerializer.new(detail).as_json)
        end
      end
    end
  end
end
