# frozen_string_literal: true

# Shared by the profile photo approval and rejection endpoints: authorizes the
# reviewer, records the decision and renders the candidate's photo state.
module CandidateProfilePhotoReview
  extend ActiveSupport::Concern

  private

  def review!(decision:)
    authorize ::Candidate, :verify?, policy_class: ::Admin::CandidateDocumentPolicy

    candidate = ::Candidate.find_by!(public_id: params.expect(:candidate_id))
    ::Admin::CandidateProfilePhotos::DecisionService.call(
      actor: current_user, candidate:, decision:, request_id: request.request_id
    )
    response.set_header('Cache-Control', 'private, no-store')
    render_success(data: ::Admin::CandidateProfilePhotoSerializer.new(candidate.reload).as_json, status: :created)
  end
end
