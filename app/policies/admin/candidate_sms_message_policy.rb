# frozen_string_literal: true

module Admin
  # Authorizes sending an SMS to a candidate by hand and reading the
  # candidate's SMS history -- one `send_candidate_sms` permission, like
  # calling a candidate (Admin::CandidateAiCallPolicy).
  class CandidateSmsMessagePolicy < ApplicationPolicy
    def index? = permission_granted?('send_candidate_sms')
    def create? = permission_granted?('send_candidate_sms')
  end
end
