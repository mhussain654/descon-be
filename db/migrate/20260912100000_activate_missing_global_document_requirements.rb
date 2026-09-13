# frozen_string_literal: true

# 'passport', 'cnic_front' and 'police_character' (Police Character
# Certificate / PCC) already exist as document_types -- passport and
# cnic_front are even OCR-extraction-enabled (DocumentType::
# OCR_EXTRACTION_DOCUMENT_TYPE_CODES) -- but no global DocumentRequirement
# row was ever seeded for them, active or otherwise, so they have never
# appeared on any candidate's document checklist. This activates the
# missing global (country/project/craft-unscoped) requirement for each,
# matching how the other six document types are already required (see
# db/seeds.rb).
class ActivateMissingGlobalDocumentRequirements < ActiveRecord::Migration[8.1]
  class DocumentType < ApplicationRecord
    self.table_name = 'document_types'
  end

  class DocumentRequirement < ApplicationRecord
    self.table_name = 'document_requirements'
  end

  ACTIVATED_CODES = %w[passport cnic_front police_character].freeze

  def up
    DocumentType.where(code: ACTIVATED_CODES).find_each do |document_type|
      requirement = DocumentRequirement.find_or_initialize_by(
        document_type_id: document_type.id, country_id: nil, project_id: nil, craft_id: nil
      )
      requirement.update!(required: true, active: true)
    end
  end

  def down
    document_type_ids = DocumentType.where(code: ACTIVATED_CODES).select(:id)
    DocumentRequirement.where(document_type_id: document_type_ids, country_id: nil, project_id: nil, craft_id: nil)
                       .update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
  end
end
