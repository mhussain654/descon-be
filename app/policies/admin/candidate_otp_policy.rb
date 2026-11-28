# frozen_string_literal: true

module Admin
  # Developer-only: the candidate page's OTP tab -- the sign-in codes sent to a
  # candidate (never their values) and sending a new one, shown once.
  class CandidateOtpPolicy < ApplicationPolicy
    def index? = permission_granted?('send_candidate_otp')
    def create? = index?
  end
end
