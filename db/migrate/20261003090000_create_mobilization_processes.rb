# frozen_string_literal: true

# Versioned, per-country mobilization processes: the ordered stage sequence a
# candidate assignment moves through. `workflow_stages` stays the reusable
# catalog of stage meanings (code + localized name); the order and the action
# each stage expects now belong to a published process version, so Qatar and
# KSA (and the provisional common process) can follow different sequences.
#
# Published (active/retired) processes are immutable -- enforced in the
# models -- and a change means publishing a new version. At most one active
# process per country, and at most one active common (country-less) process.
class CreateMobilizationProcesses < ActiveRecord::Migration[8.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :mobilization_processes do |t|
      t.string :code, null: false
      t.integer :version, null: false
      t.references :country, foreign_key: true
      t.string :status, null: false, default: 'draft'
      t.boolean :provisional, null: false, default: false
      t.datetime :effective_from
      t.datetime :effective_until
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :published_by, foreign_key: { to_table: :users }
      t.datetime :published_at
      t.timestamps
    end

    add_index :mobilization_processes, %i[code version], unique: true
    add_index :mobilization_processes, :country_id, unique: true, where: "status = 'active' AND country_id IS NOT NULL",
                                                    name: 'index_mobilization_processes_one_active_per_country'
    add_index :mobilization_processes, :status, unique: true, where: "status = 'active' AND country_id IS NULL",
                                                name: 'index_mobilization_processes_one_active_common'
    add_check_constraint :mobilization_processes, "status IN ('draft', 'active', 'retired')",
                         name: 'mobilization_processes_status'
    add_check_constraint :mobilization_processes, 'version > 0', name: 'mobilization_processes_version_positive'
    add_check_constraint :mobilization_processes, "code ~ '^[a-z0-9_]+$'", name: 'mobilization_processes_code_format'

    create_table :mobilization_process_stages do |t|
      t.references :mobilization_process, null: false, foreign_key: true
      t.references :workflow_stage, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :action_type, null: false, default: 'none'
      t.boolean :required, null: false, default: true
      t.jsonb :configuration, null: false, default: {}
      t.timestamps
    end

    add_index :mobilization_process_stages, %i[mobilization_process_id position],
              unique: true, name: 'index_process_stages_on_process_and_position'
    add_index :mobilization_process_stages, %i[mobilization_process_id workflow_stage_id],
              unique: true, name: 'index_process_stages_on_process_and_stage'
    add_check_constraint :mobilization_process_stages, 'position > 0',
                         name: 'mobilization_process_stages_position_positive'
    add_check_constraint :mobilization_process_stages, "action_type ~ '^[a-z0-9_]+$'",
                         name: 'mobilization_process_stages_action_type_format'
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
