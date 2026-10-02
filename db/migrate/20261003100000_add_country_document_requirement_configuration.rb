# frozen_string_literal: true

# Country-specific document checklists (BE PR 2).
#
# * `crafts.is_driver` -- admin-managed flag; the backend uses it to decide
#   whether driver-only requirements (the Qatar driving licence) apply.
# * `document_requirements` gains everything a client needs to render and
#   validate one checklist item without hard-coded rules: a three-way
#   `requirement_level` (replacing the `required` boolean -- a winning
#   `not_applicable` row removes an inherited requirement), display order,
#   bilingual instructions and the multi-file upload rules. `driver_only`
#   limits a row to assignments whose craft is a driver craft. `active` stays
#   purely "is this configuration row enabled".
class AddCountryDocumentRequirementConfiguration < ActiveRecord::Migration[8.1]
  DEFAULT_CONTENT_TYPES = %w[application/pdf image/jpeg image/png].freeze

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def up
    add_column :crafts, :is_driver, :boolean, null: false, default: false

    change_table :document_requirements, bulk: true do |t|
      t.string :requirement_level, null: false, default: 'required'
      t.boolean :driver_only, null: false, default: false
      t.integer :display_position, null: false, default: 100
      t.text :instructions_en
      t.text :instructions_ur
      t.integer :minimum_files, null: false, default: 1
      t.integer :maximum_files, null: false, default: 1
      t.boolean :combined_pdf_allowed, null: false, default: false
      t.string :allowed_side_codes, array: true, null: false, default: []
      t.string :accepted_content_types, array: true, null: false, default: DEFAULT_CONTENT_TYPES
      t.bigint :maximum_file_size, null: false, default: 5.megabytes
    end
    execute <<~SQL.squish
      UPDATE document_requirements
      SET requirement_level = CASE WHEN required THEN 'required' ELSE 'optional' END
    SQL
    remove_column :document_requirements, :required

    add_check_constraint :document_requirements,
                         "requirement_level IN ('required', 'optional', 'not_applicable')",
                         name: 'document_requirements_requirement_level'
    add_check_constraint :document_requirements, 'minimum_files >= 1 AND maximum_files >= minimum_files',
                         name: 'document_requirements_file_count_range'
    add_check_constraint :document_requirements, 'maximum_file_size > 0',
                         name: 'document_requirements_maximum_file_size_positive'
  end

  def down
    remove_check_constraint :document_requirements, name: 'document_requirements_maximum_file_size_positive'
    remove_check_constraint :document_requirements, name: 'document_requirements_file_count_range'
    remove_check_constraint :document_requirements, name: 'document_requirements_requirement_level'
    add_column :document_requirements, :required, :boolean, null: false, default: true
    execute "UPDATE document_requirements SET required = (requirement_level = 'required')"
    change_table :document_requirements, bulk: true do |t|
      t.remove :requirement_level, :driver_only, :display_position, :instructions_en, :instructions_ur,
               :minimum_files, :maximum_files, :combined_pdf_allowed, :allowed_side_codes,
               :accepted_content_types, :maximum_file_size
    end
    remove_column :crafts, :is_driver
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
