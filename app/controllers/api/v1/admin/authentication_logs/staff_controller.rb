# frozen_string_literal: true

module Api
  module V1
    module Admin
      module AuthenticationLogs
        # Developer-only, read-only Staff tab of the admin Authentication page:
        # sign-ins and last activity per staff account (index), and one
        # account's recent authentication events (show).
        class StaffController < ProtectedStaffController
          HISTORY_LIMIT = 50
          # A signed-in browser refreshes its session every few minutes; those
          # rows would bury the sign-ins, so the history leaves them out.
          HIDDEN_EVENT_CODES = %w[refresh_succeeded].freeze

          def index
            authorize ::User, :index?, policy_class: ::Admin::AuthenticationLogPolicy

            query = ::Admin::AuthenticationLogs::StaffIndexQuery.new(scope: staff_scope, params:)
            rows = query.call

            render_collection(
              data: rows.map { |row| ::Admin::AuthenticationLogs::StaffRowSerializer.new(row).as_json },
              pagination: query.pagination
            )
          end

          def show
            authorize ::User, :show?, policy_class: ::Admin::AuthenticationLogPolicy

            user = staff_scope.find_by!(public_id: params.expect(:id))
            row = ::Admin::AuthenticationLogs::StaffIndexQuery.new(scope: staff_scope.where(id: user.id),
                                                                   params: {}).call.first
            render_success(data: ::Admin::AuthenticationLogs::StaffRowSerializer.new(row).as_json.merge(history(user)))
          end

          private

          def staff_scope
            policy_scope(::User, policy_scope_class: ::Admin::AuthenticationLogPolicy::Scope)
          end

          def history(user)
            events = AuthenticationEvent.where(user:).where.not(event_code: HIDDEN_EVENT_CODES)
                                        .order(occurred_at: :desc, id: :desc).limit(HISTORY_LIMIT)
            ::Admin::AuthenticationLogs::StaffHistorySerializer.new(events).as_json
          end
        end
      end
    end
  end
end
