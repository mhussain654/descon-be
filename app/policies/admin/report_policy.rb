# frozen_string_literal: true

module Admin
  class ReportPolicy < ApplicationPolicy
    def index?
      permission_granted?('view_reports')
    end

    def show?
      index?
    end

    def export?
      index?
    end

    class Scope < Scope
      def resolve
        return [] unless permission_granted?('view_reports')

        scope
      end
    end
  end
end
