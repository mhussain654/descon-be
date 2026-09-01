# frozen_string_literal: true

module Api
  module V1
    module Admin
      class ProjectsController < ReferenceDataController
        private

        def record_class = ::Project
      end
    end
  end
end
