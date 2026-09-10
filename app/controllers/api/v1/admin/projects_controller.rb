# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Reference-data CRUD for deployment Projects, reusing the shared
      # list/create/update/retire behavior of ReferenceDataController.
      class ProjectsController < ReferenceDataController
        private

        # Tells the shared reference-data actions which model to operate on.
        def record_class = ::Project
      end
    end
  end
end
