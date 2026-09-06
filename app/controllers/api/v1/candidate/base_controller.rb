# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Base class for all candidate-facing API controllers; currently adds no behavior of its
      # own but establishes a distinct inheritance branch from the staff-facing BaseController.
      class BaseController < ApplicationController
      end
    end
  end
end
