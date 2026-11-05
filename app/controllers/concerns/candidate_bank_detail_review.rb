# frozen_string_literal: true

# Shared by the bank detail verification and rejection endpoints: authorizes
# the reviewer, runs the decision idempotently and renders the updated details.
module CandidateBankDetailReview
  extend ActiveSupport::Concern

  include IdempotentRequestHandling

  private

  def review!(decision:, scope:, rejection_reason: nil)
    authorize CandidateBankDetail, :review?, policy_class: ::Admin::CandidateBankDetailPolicy

    render_idempotent_response(scope:, subject: current_user, required: true) do
      bank_detail = ::Admin::CandidateBankDetails::DecisionService.call(
        actor: current_user, candidate: review_candidate, decision:, rejection_reason:, request_id: request.request_id
      )
      success_payload(data: ::Admin::CandidateBankDetailSerializer.new(bank_detail).as_json, status: :created)
    end
  end

  def review_candidate
    ::Candidate.find_by!(public_id: params.expect(:candidate_id))
  end
end
