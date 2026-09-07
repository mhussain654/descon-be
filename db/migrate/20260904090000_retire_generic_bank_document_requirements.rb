# frozen_string_literal: true

# Retires the generic 'bank_details'/'cheque_image' document-checklist
# requirements now that candidates submit bank information through the
# dedicated, structured CandidateBankDetail resource
# (Candidates::BankDetails::UpsertService, already fully built) instead.
# Deactivating the DocumentRequirement rows (not deleting the DocumentType
# rows, which stay valid history for existing CandidateDocument uploads)
# removes both from RequirementResolver's candidate-checklist output with
# no other code change (app/services/candidates/documents/
# requirement_resolver.rb already filters on `DocumentRequirement.where(
# active: true)`).
class RetireGenericBankDocumentRequirements < ActiveRecord::Migration[8.1]
  class DocumentType < ApplicationRecord
    self.table_name = 'document_types'
  end

  class DocumentRequirement < ApplicationRecord
    self.table_name = 'document_requirements'
  end

  RETIRED_CODES = %w[bank_details cheque_image].freeze

  def up
    requirements_for(RETIRED_CODES).update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    requirements_for(RETIRED_CODES).update_all(active: true) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def requirements_for(codes)
    document_type_ids = DocumentType.where(code: codes).pluck(:id)
    DocumentRequirement.where(document_type_id: document_type_ids)
  end
end
