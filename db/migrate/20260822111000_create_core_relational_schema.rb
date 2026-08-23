# frozen_string_literal: true

class CreateCoreRelationalSchema < ActiveRecord::Migration[8.1]
  CANONICAL_WORKFLOW_STAGES = [
    { code: 'registered', position: 1 },
    { code: 'documents_pending', position: 2 },
    { code: 'documents_uploaded', position: 3 },
    { code: 'under_verification', position: 4 },
    { code: 'verified', position: 5 },
    { code: 'fee_pending', position: 6 },
    { code: 'fee_paid', position: 7 },
    { code: 'documents_shared_with_qatar_bu', position: 8 },
    { code: 'qvc_appointment_booked', position: 9 },
    { code: 'qvc_completed_outcome_received', position: 10 },
    { code: 'visa_issued_or_rejected', position: 11 },
    { code: 'appeared_for_protection', position: 12 },
    { code: 'protected_ready_to_fly', position: 13 },
    { code: 'flight_details_uploaded', position: 14 },
    { code: 'mobilized', position: 15 }
  ].freeze

  def up
    create_reference_tables
    create_candidates_table
    create_document_tables
    create_candidate_assignment_tables
    create_payment_and_communication_tables
    create_audit_events_table
    add_core_constraints
    seed_workflow_stages
  end

  def down
    drop_table :audit_events
    drop_table :communications
    drop_table :payments
    drop_table :candidate_documents
    drop_table :candidate_stage_histories
    drop_table :candidate_assignments
    drop_table :document_requirements
    drop_table :document_types
    drop_table :candidates
    drop_table :workflow_stages
    drop_table :crafts
    drop_table :projects
    drop_table :countries
  end

  private

  def create_reference_tables
    create_table :countries do |t|
      t.string :code, null: false
      t.string :name_en, null: false
      t.string :name_ur, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :countries, :code, unique: true

    create_table :projects do |t|
      t.string :code, null: false
      t.string :name_en, null: false
      t.string :name_ur, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :projects, :code, unique: true

    create_table :crafts do |t|
      t.string :code, null: false
      t.string :name_en, null: false
      t.string :name_ur, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :crafts, :code, unique: true

    create_table :workflow_stages do |t|
      t.string :code, null: false
      t.integer :position, null: false
      t.boolean :system_defined, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :workflow_stages, :code, unique: true
    add_index :workflow_stages, :position, unique: true
  end

  def create_candidates_table
    create_table :candidates do |t|
      t.string :public_id, null: false
      t.string :full_name, null: false
      t.string :cnic, null: false
      t.string :mobile_number, null: false
      t.string :passport_number
      t.string :preferred_locale, null: false, default: 'en'
      t.string :source_code, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :candidates, :public_id, unique: true
    add_index :candidates, :cnic, unique: true
    add_index :candidates, :passport_number, unique: true, where: 'passport_number IS NOT NULL'
    add_index :candidates, :mobile_number
    add_index :candidates, %i[created_by_id created_at]
  end

  def create_document_tables
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

    create_table :document_requirements do |t|
      t.references :document_type, null: false, foreign_key: true
      t.references :country, foreign_key: true
      t.references :project, foreign_key: true
      t.references :craft, foreign_key: true
      t.boolean :required, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_document_requirements_on_unique_scope
      ON document_requirements (
        document_type_id,
        COALESCE(country_id, 0),
        COALESCE(project_id, 0),
        COALESCE(craft_id, 0)
      )
    SQL
  end

  def create_candidate_assignment_tables
    create_table :candidate_assignments do |t|
      t.string :public_id, null: false
      t.references :candidate, null: false, foreign_key: true
      t.references :country, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :craft, null: false, foreign_key: true
      t.string :reference_number, null: false
      t.references :current_workflow_stage, null: false, foreign_key: { to_table: :workflow_stages }
      t.string :qvc_outcome_code
      t.date :qvc_outcome_date
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :candidate_assignments, :public_id, unique: true
    add_index :candidate_assignments, :reference_number, unique: true
    add_index :candidate_assignments, %i[candidate_id created_at]
    add_index :candidate_assignments,
              %i[current_workflow_stage_id created_at],
              name: 'index_candidate_assignments_on_stage_and_created_at'
    add_index :candidate_assignments,
              %i[project_id craft_id country_id],
              name: 'index_candidate_assignments_on_project_craft_country'

    create_table :candidate_stage_histories do |t|
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :workflow_stage, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.datetime :occurred_at, null: false
      t.string :reason_code
      t.text :note

      t.timestamps
    end

    add_index :candidate_stage_histories,
              %i[candidate_assignment_id occurred_at],
              name: 'index_candidate_stage_histories_on_assignment_and_occurred_at'
    add_index :candidate_stage_histories,
              %i[workflow_stage_id occurred_at],
              name: 'index_candidate_stage_histories_on_stage_and_occurred_at'

    create_table :candidate_documents do |t|
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :document_type, null: false, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.references :verified_by, foreign_key: { to_table: :users }
      t.string :status_code, null: false
      t.string :original_filename
      t.string :content_type
      t.bigint :byte_size
      t.string :checksum_sha256
      t.string :document_number
      t.date :issued_on
      t.date :expires_on
      t.datetime :uploaded_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.datetime :verified_at
      t.text :rejection_reason

      t.timestamps
    end

    add_index :candidate_documents,
              %i[candidate_assignment_id document_type_id status_code],
              name: 'index_candidate_documents_on_assignment_type_status'
    add_index :candidate_documents, :checksum_sha256
  end

  def create_payment_and_communication_tables
    create_table :payments do |t|
      t.string :public_id, null: false
      t.references :candidate_assignment, null: false, foreign_key: true
      t.string :payment_type_code, null: false
      t.string :status_code, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency_code, null: false
      t.string :external_reference
      t.datetime :paid_at
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.text :note

      t.timestamps
    end

    add_index :payments, :public_id, unique: true
    add_index :payments,
              %i[candidate_assignment_id status_code created_at],
              name: 'index_payments_on_assignment_status_created_at'
    add_index :payments, :external_reference, unique: true, where: 'external_reference IS NOT NULL'

    create_table :communications do |t|
      t.string :public_id, null: false
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :initiated_by, foreign_key: { to_table: :users }
      t.string :channel_code, null: false
      t.string :direction_code, null: false
      t.string :status_code, null: false
      t.string :template_code
      t.string :locale, null: false, default: 'en'
      t.string :recipient_masked
      t.string :provider_reference
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :failed_at
      t.string :error_code

      t.timestamps
    end

    add_index :communications, :public_id, unique: true
    add_index :communications,
              %i[candidate_assignment_id channel_code created_at],
              name: 'index_communications_on_assignment_channel_created_at'
    add_index :communications, :provider_reference
  end

  def create_audit_events_table
    create_table :audit_events do |t|
      t.references :candidate, foreign_key: true
      t.references :candidate_assignment, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :entity_type, null: false
      t.bigint :entity_id, null: false
      t.string :action_code, null: false
      t.string :reason_code
      t.text :note
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :audit_events, %i[entity_type entity_id occurred_at], name: 'index_audit_events_on_entity_and_occurred_at'
    add_index :audit_events,
              %i[candidate_assignment_id occurred_at],
              name: 'index_audit_events_on_assignment_and_occurred_at'
    add_index :audit_events, %i[candidate_id occurred_at], name: 'index_audit_events_on_candidate_and_occurred_at'
    add_index :audit_events, %i[actor_id occurred_at], name: 'index_audit_events_on_actor_and_occurred_at'
  end

  def add_core_constraints
    add_check_constraint :candidates, "cnic ~ '^\\d{5}-\\d{7}-\\d$'", name: 'candidates_cnic_format'
    add_check_constraint :candidates, "mobile_number ~ '^\\+?\\d{10,15}$'", name: 'candidates_mobile_number_format'
    add_check_constraint :candidates, "preferred_locale IN ('en', 'ur')", name: 'candidates_preferred_locale'
    add_check_constraint :candidates, "source_code IN ('admin_ui', 'csv_import')", name: 'candidates_source_code'

    add_check_constraint :candidate_assignments,
                         '(
                           (qvc_outcome_code IS NULL AND qvc_outcome_date IS NULL) OR
                           (qvc_outcome_code IS NOT NULL AND qvc_outcome_date IS NOT NULL)
                         )',
                         name: 'candidate_assignments_qvc_pair'

    add_check_constraint :candidate_documents,
                         "status_code IN ('uploaded', 'under_verification', 'verified', 'rejected')",
                         name: 'candidate_documents_status_code'

    add_check_constraint :payments, 'amount > 0', name: 'payments_amount_positive'
    add_check_constraint :payments, "currency_code ~ '^[A-Z]{3}$'", name: 'payments_currency_code_format'

    add_check_constraint :communications, "locale IN ('en', 'ur')", name: 'communications_locale'
    add_check_constraint :communications,
                         "direction_code IN ('inbound', 'outbound')",
                         name: 'communications_direction_code'
  end

  def seed_workflow_stages
    now = connection.quote(Time.current)

    execute <<~SQL.squish
      INSERT INTO workflow_stages (code, position, system_defined, active, created_at, updated_at)
      VALUES #{CANONICAL_WORKFLOW_STAGES.map { |stage| workflow_stage_values(stage, now) }.join(', ')}
      ON CONFLICT (code) DO NOTHING
    SQL
  end

  def workflow_stage_values(stage, now)
    [
      connection.quote(stage.fetch(:code)),
      stage.fetch(:position),
      connection.quote(true),
      connection.quote(true),
      now,
      now
    ].join(', ').prepend('(').concat(')')
  end
end
