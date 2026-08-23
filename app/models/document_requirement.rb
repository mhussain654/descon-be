# frozen_string_literal: true

class DocumentRequirement < ApplicationRecord
  belongs_to :document_type
  belongs_to :country, optional: true
  belongs_to :project, optional: true
  belongs_to :craft, optional: true

  validates :document_type_id,
            uniqueness: {
              scope: %i[country_id project_id craft_id],
              message: :taken
            }
  validates :required, :active, inclusion: { in: [true, false] }
end
