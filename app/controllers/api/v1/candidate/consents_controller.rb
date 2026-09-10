# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets the logged-in candidate view their consent status and accept the current policy
      # version. Must stay reachable even while the candidate is gated by
      # ProtectedController#ensure_consent_given! -- otherwise a candidate who hasn't accepted
      # yet could never submit that acceptance.
      class ConsentsController < ProtectedController
        skip_before_action :ensure_consent_given!

        # Returns whether the current policy version has been accepted, and when.
        def show
          authorize current_candidate, policy_class: ::Candidates::ConsentPolicy

          render_success(data: ::Candidates::ConsentSerializer.new(current_candidate).as_json)
        end

        # Records the candidate's acceptance of the current policy version, idempotently.
        def create
          authorize current_candidate, policy_class: ::Candidates::ConsentPolicy

          ::Candidates::Consents::RecordService.call(candidate: current_candidate, ip_address: request.remote_ip)

          render_success(
            data: ::Candidates::ConsentSerializer.new(current_candidate).as_json.merge(
              message: t('api.candidate_consents.accepted')
            ),
            status: :created
          )
        end
      end
    end
  end
end
