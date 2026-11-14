# frozen_string_literal: true

module Admin
  # Authorizes reading the background job logs (Solid Queue job runs and
  # failures): developers only (the developer-only `view_job_logs` permission).
  class JobLogPolicy < ApplicationPolicy
    def index? = permission_granted?('view_job_logs')

    # Every job row for developers; nothing for anyone else.
    class Scope < ApplicationPolicy::Scope
      def resolve
        return scope.none unless permission_granted?('view_job_logs')

        scope
      end
    end
  end
end
