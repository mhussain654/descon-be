# frozen_string_literal: true

module Candidates
  module Documents
    ChecklistItem = Data.define(:requirement_code, :name, :required, :status, :replacement_allowed, :document)
  end
end
