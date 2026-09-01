# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateImportTemplatesController < ProtectedStaffController
        def show
          authorize :candidate_import, :show?, policy_class: ::Admin::CandidateImportPolicy

          send_data(
            ::Admin::Candidates::Imports::Template.call,
            filename: ::Admin::Candidates::Imports::Template.filename,
            type: 'text/csv; charset=utf-8',
            disposition: 'attachment'
          )
        end
      end
    end
  end
end
