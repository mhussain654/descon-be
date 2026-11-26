# frozen_string_literal: true

module Admin
  # One checklist row for the developer-only checklist editor.
  class DocumentRequirementSerializer
    def self.ref(record) = record && { code: record.code, name: record.name_for }

    def initialize(requirement)
      @requirement = requirement
    end

    def as_json(*)
      scope.merge(settings).merge(id: @requirement.id.to_s, updated_at: @requirement.updated_at.utc.iso8601)
    end

    private

    def scope
      {
        document_type: self.class.ref(@requirement.document_type),
        country: self.class.ref(@requirement.country),
        project: self.class.ref(@requirement.project),
        craft: self.class.ref(@requirement.craft),
        driver_only: @requirement.driver_only
      }
    end

    def settings
      @requirement.slice(:requirement_level, :active, :minimum_files, :maximum_files, :accepted_content_types,
                         :instructions_en, :instructions_ur).symbolize_keys
    end
  end
end
