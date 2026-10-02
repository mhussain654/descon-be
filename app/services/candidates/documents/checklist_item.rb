# frozen_string_literal: true

module Candidates
  module Documents
    # One checklist entry: the requirement's backend-decided configuration
    # (order, instructions, upload rules) plus the current document, if any.
    ChecklistItem = Data.define(
      :requirement_code, :name, :required, :display_position, :instructions, :upload_rules,
      :status, :replacement_allowed, :document
    )
  end
end
