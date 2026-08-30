# frozen_string_literal: true

class CreateCandidateWorkflowEvents < ActiveRecord::Migration[8.1]
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :candidate_workflow_events do |t|
      t.references :candidate, null: false, foreign_key: true
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :candidate_stage_history, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :event_code, null: false
      t.string :request_id, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :published_at

      t.timestamps
    end

    add_index :candidate_workflow_events, :event_code
    add_index :candidate_workflow_events, %i[candidate_assignment_id occurred_at],
              name: 'index_workflow_events_on_assignment_and_occurred_at'
    add_index :candidate_workflow_events, %i[candidate_stage_history_id event_code],
              unique: true,
              name: 'index_workflow_events_on_history_and_event_code'
    add_check_constraint :candidate_workflow_events,
                         "event_code ~ '^[a-z0-9_]+$'",
                         name: 'candidate_workflow_events_event_code_format'
  end
  # rubocop:enable Metrics/MethodLength
end
