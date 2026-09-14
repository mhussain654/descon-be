# frozen_string_literal: true

class CreateCandidateAiCalls < ActiveRecord::Migration[8.1]
  ENUM_COLUMNS = {
    direction: %w[inbound outbound],
    status: %w[requested queued ringing in_progress processing completed failed cancelled],
    language_code: %w[en ur],
    verification_status: %w[not_applicable pending verified failed skipped]
  }.freeze
  NULLABLE_ENUM_COLUMNS = { outcome: %w[answered not_answered callback_required] }.freeze
  CODE_FORMAT_COLUMNS = %i[call_reason provider_code].freeze
  NULLABLE_CODE_FORMAT_COLUMNS = %i[outcome_reason failure_code].freeze

  def change
    create_candidate_ai_calls_table
    add_candidate_ai_call_indexes
    add_candidate_ai_call_constraints
  end

  private

  def create_candidate_ai_calls_table
    create_table :candidate_ai_calls do |t|
      add_candidate_ai_call_references(t)
      add_candidate_ai_call_lifecycle_fields(t)
      add_candidate_ai_call_provider_fields(t)
      add_candidate_ai_call_configuration_and_review_fields(t)
      add_candidate_ai_call_remaining_fields(t)

      t.timestamps
    end
  end

  def add_candidate_ai_call_references(table)
    table.string :public_id, null: false
    table.references :communication, null: false, foreign_key: true, index: { unique: true }
    table.references :candidate, foreign_key: true
    table.references :candidate_assignment, foreign_key: true
    table.references :triggered_by, foreign_key: { to_table: :users }
  end

  def add_candidate_ai_call_lifecycle_fields(table)
    table.string :direction, null: false
    table.string :call_reason, null: false
    table.string :language_code, null: false, default: 'en'
    table.string :status, null: false, default: 'requested'
    table.string :outcome
    table.string :outcome_reason
  end

  def add_candidate_ai_call_provider_fields(table)
    table.string :provider_code, null: false, default: 'elevenlabs'
    table.string :elevenlabs_agent_id
    table.string :elevenlabs_conversation_id
    table.string :elevenlabs_agent_phone_number_id
    table.string :twilio_call_sid
    table.string :provider_status
    table.string :failure_code
    table.text :failure_message
  end

  # Configuration-tracking fields record which prompt/agent/extraction-schema
  # version produced a call, so behaviour differences are explainable after
  # the fact (`agent_config_digest` is our own SHA-256 of the deployed
  # config, independent of ElevenLabs' own version identifier). Review
  # fields resolve a `needs_manual_review` outcome.
  def add_candidate_ai_call_configuration_and_review_fields(table)
    table.string :prompt_template_code
    table.string :prompt_template_version
    table.string :elevenlabs_agent_version
    table.string :extraction_schema_version
    table.string :agent_config_digest
    table.references :reviewed_by, foreign_key: { to_table: :users }
    table.datetime :reviewed_at
    table.string :review_resolution
    table.text :review_notes
  end

  def add_candidate_ai_call_remaining_fields(table)
    table.text :summary
    table.jsonb :extracted_data, null: false, default: {}
    table.string :caller_number_masked
    table.string :verification_status, null: false, default: 'not_applicable'
    table.integer :verification_attempts, null: false, default: 0
    table.datetime :callback_requested_at
    table.datetime :started_at
    table.datetime :answered_at
    table.datetime :completed_at
  end

  def add_candidate_ai_call_indexes
    add_index :candidate_ai_calls, :public_id, unique: true
    add_index :candidate_ai_calls, %i[candidate_id created_at],
              name: 'index_candidate_ai_calls_on_candidate_and_created_at'
    add_index :candidate_ai_calls, %i[status updated_at], name: 'index_candidate_ai_calls_on_status_and_updated_at'
    add_index :candidate_ai_calls, :elevenlabs_conversation_id, unique: true,
                                                                where: 'elevenlabs_conversation_id IS NOT NULL'
    add_index :candidate_ai_calls, :twilio_call_sid, unique: true, where: 'twilio_call_sid IS NOT NULL'
  end

  def add_candidate_ai_call_constraints
    ENUM_COLUMNS.each { |column, values| add_enum_constraint(column, values, nullable: false) }
    NULLABLE_ENUM_COLUMNS.each { |column, values| add_enum_constraint(column, values, nullable: true) }
    CODE_FORMAT_COLUMNS.each { |column| add_format_constraint(column, nullable: false) }
    NULLABLE_CODE_FORMAT_COLUMNS.each { |column| add_format_constraint(column, nullable: true) }
    add_check_constraint :candidate_ai_calls, 'verification_attempts >= 0',
                         name: 'candidate_ai_calls_verification_attempts_non_negative'
  end

  def add_enum_constraint(column, values, nullable:)
    list = values.map { |value| "'#{value}'" }.join(', ')
    condition = nullable ? "#{column} IS NULL OR #{column} IN (#{list})" : "#{column} IN (#{list})"
    add_check_constraint :candidate_ai_calls, condition, name: "candidate_ai_calls_#{column}"
  end

  def add_format_constraint(column, nullable:)
    format = "#{column} ~ '^[a-z0-9_]+$'"
    condition = nullable ? "#{column} IS NULL OR #{format}" : format
    add_check_constraint :candidate_ai_calls, condition, name: "candidate_ai_calls_#{column}_format"
  end
end
