# frozen_string_literal: true

module Api
  module V1
    module Admin
      module AuthenticationLogs
        # Developer-only, read-only Candidates tab of the admin Authentication
        # page: OTPs sent, sign-ins and last app use per candidate (index), and
        # one candidate's recent sign-ins and OTPs (show).
        class CandidatesController < ProtectedStaffController
          HISTORY_LIMIT = 50

          def index
            authorize ::Candidate, :index?, policy_class: ::Admin::AuthenticationLogPolicy

            query = ::Admin::AuthenticationLogs::CandidateIndexQuery.new(scope: candidate_scope, params:)
            rows = query.call

            render_collection(
              data: rows.map { |row| ::Admin::AuthenticationLogs::CandidateRowSerializer.new(row).as_json },
              pagination: query.pagination,
              meta: { applied_filters: query.applied_filters }
            )
          end

          def show
            authorize ::Candidate, :show?, policy_class: ::Admin::AuthenticationLogPolicy

            candidate = candidate_scope.find_by!(public_id: params.expect(:id))
            row = ::Admin::AuthenticationLogs::CandidateIndexQuery.new(scope: candidate_scope.where(id: candidate.id),
                                                                       params: {}).call.first
            render_success(data: ::Admin::AuthenticationLogs::CandidateRowSerializer.new(row).as_json.merge(history(candidate)))
          end

          private

          def candidate_scope
            policy_scope(::Candidate, policy_scope_class: ::Admin::AuthenticationLogPolicy::Scope)
          end

          def history(candidate)
            ::Admin::AuthenticationLogs::CandidateHistorySerializer.new(
              sessions: candidate.candidate_sessions.order(created_at: :desc, id: :desc).limit(HISTORY_LIMIT),
              otp_challenges: CandidateOtpChallenge.where(candidate:).order(created_at: :desc, id: :desc)
                                                   .limit(HISTORY_LIMIT)
            ).as_json
          end
        end
      end
    end
  end
end
