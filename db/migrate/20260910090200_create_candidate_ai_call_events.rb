# frozen_string_literal: true

# Append-only ledger serving two purposes at once, mirroring the
# Payment/PaymentEvent pattern exactly: (1) the audit trail of everything
# that happened on a call, (2) webhook/tool-call idempotency via the unique
# (provider_code, event_key) index -- a duplicate delivery inserts nothing
# and the caller treats that as "already handled" rather than reprocessing.
class CreateCandidateAiCallEvents < ActiveRecord::Migration[8.1]
  REQUIRED_STRING_FIELDS = %i[provider_code event_source event_type event_key].freeze

  def change
    create_candidate_ai_call_events_table
    add_candidate_ai_call_event_indexes
    add_candidate_ai_call_event_constraints
  end

  private

  def create_candidate_ai_call_events_table
    create_table :candidate_ai_call_events do |t|
      t.references :candidate_ai_call, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      REQUIRED_STRING_FIELDS.each { |field| t.string field, null: false }
      t.datetime :occurred_at, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :request_id

      t.timestamps
    end
  end

  def add_candidate_ai_call_event_indexes
    add_index :candidate_ai_call_events, %i[provider_code event_key], unique: true
    add_index :candidate_ai_call_events,
              %i[candidate_ai_call_id occurred_at],
              name: 'index_candidate_ai_call_events_on_call_and_occurred_at'
  end

  def add_candidate_ai_call_event_constraints
    add_check_constraint :candidate_ai_call_events, "provider_code ~ '^[a-z0-9_]+$'",
                         name: 'candidate_ai_call_events_provider_code_format'
    add_check_constraint :candidate_ai_call_events, "event_source ~ '^[a-z0-9_]+$'",
                         name: 'candidate_ai_call_events_event_source_format'
    add_check_constraint :candidate_ai_call_events, "event_type ~ '^[a-z0-9_]+$'",
                         name: 'candidate_ai_call_events_event_type_format'
  end
end
