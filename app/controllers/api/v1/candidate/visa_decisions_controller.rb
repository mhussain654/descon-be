# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate view the list of visa decisions recorded against
      # their current deployment assignment.
      class VisaDecisionsController < ProtectedController
        # Returns the current candidate's visa decisions (empty before any have been recorded).
        def index
          authorize current_candidate, :history?, policy_class: ::Candidates::WorkflowPolicy

          set_private_state_headers(
            updated_at: current_candidate.current_assignment&.updated_at,
            etag_key: "#{current_candidate.public_id}:visa_decisions"
          )
          render_success(data: visa_decisions_payload)
        end

        private

        def visa_decisions_payload
          assignment = current_candidate.current_assignment
          {
            assignment_id: assignment&.public_id,
            visa_decisions: serialized_visa_decisions(assignment)
          }
        end

        # Serializes the assignment's visa decisions, or an empty list if there is no assignment.
        # Not VisaDecisionQuery -- that eager-loads :recorded_by for the admin serializer's
        # benefit, which this candidate-facing serializer never reads (Bullet flags it as
        # unused eager loading if reused here); plain chronological order is all this needs.
        def serialized_visa_decisions(assignment)
          return [] if assignment.blank?

          assignment.candidate_visa_decisions.order(:created_at).map do |decision|
            ::CandidateWorkflows::VisaDecisionSerializer.new(decision).as_json
          end
        end
      end
    end
  end
end
