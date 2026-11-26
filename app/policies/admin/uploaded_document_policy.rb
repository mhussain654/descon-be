# frozen_string_literal: true

module Admin
  # Viewing what a candidate has uploaded, submitted or not (support checks).
  # View only -- approving and rejecting stay with the review of submitted
  # documents. Developer-only (`view_uploaded_documents`).
  class UploadedDocumentPolicy < ApplicationPolicy
    def index? = permission_granted?('view_uploaded_documents')

    def access? = index?
  end
end
