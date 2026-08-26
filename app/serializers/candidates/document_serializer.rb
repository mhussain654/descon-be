# frozen_string_literal: true

module Candidates
  class DocumentSerializer
    def initialize(checklist_item)
      @checklist_item = checklist_item
    end

    def as_json(*)
      {
        requirement_code: @checklist_item.requirement_code,
        name: @checklist_item.name,
        required: @checklist_item.required,
        status: @checklist_item.status,
        replacement_allowed: @checklist_item.replacement_allowed,
        document: @checklist_item.document
      }
    end
  end
end
