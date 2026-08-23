# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Namespace-scoped base for candidate-facing endpoints, mirroring
      # Api::V1::BaseController's role for staff. Deliberately does not
      # inherit from Api::V1::BaseController: that class's current_user/
      # session helpers are staff-specific (User, Session, Authentication::
      # TokenDecoder), and candidate endpoints must never accidentally gain
      # access to them. No protected candidate endpoint exists yet -- a
      # current_candidate helper belongs to whichever ticket first needs it.
      class BaseController < ApplicationController
      end
    end
  end
end
