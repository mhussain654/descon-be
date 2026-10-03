# frozen_string_literal: true

module DocumentChecklists
  # Brings the document catalog and the common/country requirement rows in
  # line with Definitions (idempotent -- runs on every `db:seed`). Retired
  # document types are deactivated with their requirement rows, and any
  # common/country row the definitions no longer list (e.g. the old global
  # PCC row, now Qatar-only) is deactivated too -- never deleted.
  class Seeder < ApplicationService
    def call
      seed_document_types
      retire_document_types
      seeded_ids = Definitions.requirements.map { |row| seed_requirement(row).id }
      deactivate_undefined_requirements(seeded_ids)
    end

    private

    def seed_document_types
      Definitions::DOCUMENT_TYPES.each do |attributes|
        document_type = DocumentType.find_or_initialize_by(code: attributes.fetch(:code))
        document_type.assign_attributes(
          name_en: attributes.fetch(:name_en), name_ur: attributes.fetch(:name_ur),
          requires_number: attributes.fetch(:requires_number, false),
          requires_expiry: attributes.fetch(:requires_expiry, false),
          active: true
        )
        document_type.save!
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
      requirement.assign_attributes(row.fetch(:attributes))
      requirement.save!
      requirement
    end

    # Only the common/country-level rows this catalog owns (no project/craft scope).
    def deactivate_undefined_requirements(seeded_ids)
      DocumentRequirement.where(project_id: nil, craft_id: nil, active: true).where.not(id: seeded_ids)
                         .update_all(active: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
