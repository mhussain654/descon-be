# frozen_string_literal: true

class CreateReferenceCatalogs < ActiveRecord::Migration[8.1]
  CODE_FORMAT_SQL = "code ~ '^[a-z0-9_]+$'"

  def change
    create_localized_reference_table(:countries, 'countries_code_format')
    create_localized_reference_table(:projects, 'projects_code_format')
    create_localized_reference_table(:crafts, 'crafts_code_format')
    create_workflow_stages
    create_document_types
    create_document_requirements
  end

  private

  def create_localized_reference_table(table_name, constraint_name)
    create_table table_name do |t|
      t.string :code, null: false
      t.string :name_en, null: false
      t.string :name_ur, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index table_name, :code, unique: true
    add_check_constraint table_name, CODE_FORMAT_SQL, name: constraint_name
  end

  def create_workflow_stages
    create_table :workflow_stages do |t|
      t.string :code, null: false
      t.integer :position, null: false
      t.boolean :system_defined, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :workflow_stages, :code, unique: true
    add_index :workflow_stages, :position, unique: true
    add_check_constraint :workflow_stages, CODE_FORMAT_SQL, name: 'workflow_stages_code_format'
  end

  def create_document_types
    create_table :document_types do |t|
      t.string :code, null: false
      t.string :name_en, null: false
      t.string :name_ur, null: false
      t.boolean :active, null: false, default: true
      t.boolean :requires_number, null: false, default: false
      t.boolean :requires_expiry, null: false, default: false

      t.timestamps
    end

    add_index :document_types, :code, unique: true
    add_check_constraint :document_types, CODE_FORMAT_SQL, name: 'document_types_code_format'
  end

  def create_document_requirements
    create_table :document_requirements do |t|
      t.references :document_type, null: false, foreign_key: true
      t.references :country, foreign_key: true
      t.references :project, foreign_key: true
      t.references :craft, foreign_key: true
      t.boolean :required, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :document_requirements,
              'document_type_id, COALESCE(country_id, 0), COALESCE(project_id, 0), COALESCE(craft_id, 0)',
              unique: true,
              name: 'index_document_requirements_on_unique_scope'
  end
end
