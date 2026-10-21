# frozen_string_literal: true

module Admin
  # The call-type library (named RoboCall voices). Anyone who can trigger calls
  # may read it, to pick one; changing it is the separate, more sensitive
  # `manage_ai_call_scripts` grant (it decides what automatic and bulk calls
  # play), like the per-stage call setup.
  class RobocallVoicePolicy < ApplicationPolicy
    def index? = trigger_or_manage?
    def create? = permission_granted?('manage_ai_call_scripts')
    def update? = permission_granted?('manage_ai_call_scripts')

    private

    def trigger_or_manage?
      permission_granted?('trigger_ai_calls') || permission_granted?('manage_ai_call_scripts')
    end

    class Scope < Scope
      def resolve
        unless permission_granted?('trigger_ai_calls') || permission_granted?('manage_ai_call_scripts')
          return scope.none
        end

        scope.all
      end
    end
  end
end
