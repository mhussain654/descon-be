# frozen_string_literal: true

module DocumentChecklists
  # Adds the document catalog and the common/country requirement rows from
  # Definitions when they are missing (runs with `db:seed`). Never overwrites a
  # row that exists: developers edit checklists in admin (Reference data), and
  # a later seed run must not undo their edits. Retired document types (the
  # code's RETIRED_DOCUMENT_TYPE_CODES) are deactivated with their requirement
  # rows -- never deleted.
  class Seeder < ApplicationService
    def call
      seed_document_types
      retire_document_types
      Definitions.requirements.each { |row| seed_requirement(row) }
    end

    private

    def seed_document_types
      Definitions::DOCUMENT_TYPES.each do |attributes|
        DocumentType.find_or_create_by!(code: attributes.fetch(:code)) do |document_type|
          document_type.assign_attributes(
            name_en: attributes.fetch(:name_en), name_ur: attributes.fetch(:name_ur),
            requires_number: attributes.fetch(:requires_number, false),
            requires_expiry: attributes.fetch(:requires_expiry, false),
            active: true
          )
        end
      end
    end

    def retire_document_types
      retired = DocumentType.where(code: Definitions::RETIRED_DOCUMENT_TYPE_CODES)
      retired.update_all(active: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      DocumentRequirement.where(document_type: retired).update_all(active: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def seed_requirement(row)
      requirement = DocumentRequirement.find_or_initialize_by(
        document_type: DocumentType.find_by!(code: row.fetch(:document_code)),
        country: row.fetch(:country_code) && Country.find_by!(code: row.fetch(:country_code)),
        project: nil, craft: nil
      )
      return requirement unless requirement.new_record?

      requirement.assign_attributes(row.fetch(:attributes))
      requirement.save!
      requirement
    end
  end
end
