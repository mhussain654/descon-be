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
        **configuration,
        status: @checklist_item.status,
        replacement_allowed: @checklist_item.replacement_allowed,
        document: @checklist_item.document
      }
    end

    private

    # Backend-decided order, instructions and upload rules for this item.
    def configuration
      {
        display_position: @checklist_item.display_position,
        instructions: @checklist_item.instructions,
        **@checklist_item.upload_rules
      }
    end
  end
end
