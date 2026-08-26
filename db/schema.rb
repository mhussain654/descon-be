# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_26_113000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_events", force: :cascade do |t|
    t.string "action_code", null: false
    t.bigint "actor_id"
    t.bigint "candidate_assignment_id"
    t.bigint "candidate_id"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "entity_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "note"
    t.datetime "occurred_at", null: false
    t.string "reason_code"
    t.string "request_id"
    t.datetime "updated_at", null: false
    t.index ["actor_id", "occurred_at"], name: "index_audit_events_on_actor_and_occurred_at"
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["candidate_assignment_id", "occurred_at"], name: "index_audit_events_on_assignment_and_occurred_at"
    t.index ["candidate_assignment_id"], name: "index_audit_events_on_candidate_assignment_id"
    t.index ["candidate_id", "occurred_at"], name: "index_audit_events_on_candidate_and_occurred_at"
    t.index ["candidate_id"], name: "index_audit_events_on_candidate_id"
    t.index ["entity_type", "entity_id", "occurred_at"], name: "index_audit_events_on_entity_and_occurred_at"
    t.index ["request_id"], name: "index_audit_events_on_request_id"
    t.check_constraint "action_code::text ~ '^[a-z0-9_]+$'::text", name: "audit_events_action_code_format"
    t.check_constraint "reason_code IS NULL OR reason_code::text ~ '^[a-z0-9_]+$'::text", name: "audit_events_reason_code_format"
  end

  create_table "authentication_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_code", null: false
    t.string "identifier_masked"
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.string "request_id", null: false
    t.bigint "session_id"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.index ["event_code"], name: "index_authentication_events_on_event_code"
    t.index ["occurred_at"], name: "index_authentication_events_on_occurred_at"
    t.index ["session_id"], name: "index_authentication_events_on_session_id"
    t.index ["user_id"], name: "index_authentication_events_on_user_id"
  end

  create_table "candidate_assignments", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.bigint "country_id", null: false
    t.bigint "craft_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.bigint "current_workflow_stage_id", null: false
    t.bigint "project_id", null: false
    t.string "public_id", null: false
    t.string "qvc_outcome_code"
    t.date "qvc_outcome_date"
    t.string "reference_number", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "created_at"], name: "index_candidate_assignments_on_candidate_id_and_created_at"
    t.index ["candidate_id"], name: "index_candidate_assignments_on_candidate_id"
    t.index ["country_id"], name: "index_candidate_assignments_on_country_id"
    t.index ["craft_id"], name: "index_candidate_assignments_on_craft_id"
    t.index ["created_by_id"], name: "index_candidate_assignments_on_created_by_id"
    t.index ["current_workflow_stage_id", "created_at"], name: "index_candidate_assignments_on_stage_and_created_at"
    t.index ["current_workflow_stage_id"], name: "index_candidate_assignments_on_current_workflow_stage_id"
    t.index ["project_id", "craft_id", "country_id"], name: "index_candidate_assignments_on_project_craft_country"
    t.index ["project_id"], name: "index_candidate_assignments_on_project_id"
    t.index ["public_id"], name: "index_candidate_assignments_on_public_id", unique: true
    t.index ["reference_number"], name: "index_candidate_assignments_on_reference_number", unique: true
    t.check_constraint "qvc_outcome_code IS NULL AND qvc_outcome_date IS NULL OR qvc_outcome_code IS NOT NULL AND qvc_outcome_date IS NOT NULL", name: "candidate_assignments_qvc_pair"
    t.check_constraint "qvc_outcome_code IS NULL OR qvc_outcome_code::text ~ '^[a-z0-9_]+$'::text", name: "candidate_assignments_qvc_outcome_code_format"
  end

  create_table "candidate_documents", force: :cascade do |t|
    t.bigint "byte_size"
    t.bigint "candidate_assignment_id", null: false
    t.string "checksum_sha256"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "document_number"
    t.bigint "document_type_id", null: false
    t.date "expires_on"
    t.date "issued_on"
    t.string "original_filename"
    t.text "rejection_reason"
    t.string "status_code", null: false
    t.datetime "updated_at", null: false
    t.datetime "uploaded_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "uploaded_by_id"
    t.datetime "verified_at"
    t.bigint "verified_by_id"
    t.index ["candidate_assignment_id", "document_type_id", "status_code"], name: "index_candidate_documents_on_assignment_type_status"
    t.index ["candidate_assignment_id"], name: "index_candidate_documents_on_candidate_assignment_id"
    t.index ["checksum_sha256"], name: "index_candidate_documents_on_checksum_sha256"
    t.index ["document_type_id"], name: "index_candidate_documents_on_document_type_id"
    t.index ["uploaded_by_id"], name: "index_candidate_documents_on_uploaded_by_id"
    t.index ["verified_by_id"], name: "index_candidate_documents_on_verified_by_id"
    t.check_constraint "(status_code::text = ANY (ARRAY['uploaded'::character varying, 'under_verification'::character varying]::text[])) AND verified_by_id IS NULL AND verified_at IS NULL AND rejection_reason IS NULL OR status_code::text = 'verified'::text AND verified_by_id IS NOT NULL AND verified_at IS NOT NULL AND rejection_reason IS NULL OR status_code::text = 'rejected'::text AND verified_by_id IS NOT NULL AND verified_at IS NOT NULL AND rejection_reason IS NOT NULL", name: "candidate_documents_status_consistency"
    t.check_constraint "status_code::text = ANY (ARRAY['uploaded'::character varying, 'under_verification'::character varying, 'verified'::character varying, 'rejected'::character varying]::text[])", name: "candidate_documents_status_code"
  end

  create_table "candidate_otp_challenges", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.bigint "candidate_id"
    t.string "cnic", null: false
    t.string "code_digest", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "requested_ip"
    t.datetime "updated_at", null: false
    t.index ["candidate_id"], name: "index_candidate_otp_challenges_on_candidate_id"
    t.index ["cnic", "created_at"], name: "index_candidate_otp_challenges_on_cnic_and_created_at"
    t.check_constraint "attempts >= 0", name: "candidate_otp_challenges_attempts_range"
  end

  create_table "candidate_refresh_tokens", force: :cascade do |t|
    t.bigint "candidate_session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "replaced_by_id"
    t.datetime "revoked_at"
    t.datetime "rotated_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_session_id"], name: "index_candidate_refresh_tokens_on_candidate_session_id"
    t.index ["expires_at"], name: "index_candidate_refresh_tokens_on_expires_at"
    t.index ["replaced_by_id"], name: "index_candidate_refresh_tokens_on_replaced_by_id"
    t.index ["token_digest"], name: "index_candidate_refresh_tokens_on_token_digest", unique: true
  end

  create_table "candidate_sessions", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "jti", null: false
    t.datetime "last_seen_at"
    t.string "public_id", null: false
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["candidate_id", "revoked_at"], name: "index_candidate_sessions_on_candidate_id_and_revoked_at"
    t.index ["candidate_id"], name: "index_candidate_sessions_on_candidate_id"
    t.index ["jti"], name: "index_candidate_sessions_on_jti", unique: true
    t.index ["public_id"], name: "index_candidate_sessions_on_public_id", unique: true
  end

  create_table "candidate_stage_histories", force: :cascade do |t|
    t.bigint "actor_id"
    t.bigint "candidate_assignment_id", null: false
    t.datetime "created_at", null: false
    t.bigint "from_workflow_stage_id"
    t.text "note"
    t.datetime "occurred_at", null: false
    t.string "reason_code"
    t.bigint "to_workflow_stage_id", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_candidate_stage_histories_on_actor_id"
    t.index ["candidate_assignment_id", "occurred_at"], name: "index_candidate_stage_histories_on_assignment_and_occurred_at"
    t.index ["candidate_assignment_id"], name: "index_candidate_stage_histories_on_candidate_assignment_id"
    t.index ["from_workflow_stage_id", "occurred_at"], name: "index_candidate_stage_histories_on_from_stage_and_occurred_at"
    t.index ["from_workflow_stage_id"], name: "index_candidate_stage_histories_on_from_workflow_stage_id"
    t.index ["to_workflow_stage_id", "occurred_at"], name: "index_candidate_stage_histories_on_to_stage_and_occurred_at"
    t.index ["to_workflow_stage_id"], name: "index_candidate_stage_histories_on_to_workflow_stage_id"
    t.check_constraint "from_workflow_stage_id IS NULL OR from_workflow_stage_id <> to_workflow_stage_id", name: "candidate_stage_histories_distinct_transition"
    t.check_constraint "reason_code IS NULL OR reason_code::text ~ '^[a-z0-9_]+$'::text", name: "candidate_stage_histories_reason_code_format"
  end

  create_table "candidates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "cnic", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.string "full_name", null: false
    t.string "mobile_number", null: false
    t.string "passport_number"
    t.string "preferred_locale", default: "en", null: false
    t.string "public_id", null: false
    t.string "source_code", null: false
    t.string "status_code", default: "registered", null: false
    t.datetime "updated_at", null: false
    t.index ["cnic"], name: "index_candidates_on_cnic", unique: true
    t.index ["created_by_id", "created_at"], name: "index_candidates_on_created_by_id_and_created_at"
    t.index ["created_by_id"], name: "index_candidates_on_created_by_id"
    t.index ["mobile_number"], name: "index_candidates_on_mobile_number"
    t.index ["passport_number"], name: "index_candidates_on_passport_number", unique: true, where: "(passport_number IS NOT NULL)"
    t.index ["public_id"], name: "index_candidates_on_public_id", unique: true
    t.check_constraint "cnic::text ~ '^\\d{5}-\\d{7}-\\d$'::text", name: "candidates_cnic_format"
    t.check_constraint "mobile_number::text ~ '^\\+?\\d{10,15}$'::text", name: "candidates_mobile_number_format"
    t.check_constraint "preferred_locale::text = ANY (ARRAY['en'::character varying, 'ur'::character varying]::text[])", name: "candidates_preferred_locale"
    t.check_constraint "source_code::text = ANY (ARRAY['admin_ui'::character varying, 'csv_import'::character varying]::text[])", name: "candidates_source_code"
    t.check_constraint "status_code::text ~ '^[a-z0-9_]+$'::text", name: "candidates_status_code_format"
  end

  create_table "communications", force: :cascade do |t|
    t.bigint "candidate_assignment_id", null: false
    t.string "channel_code", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "direction_code", null: false
    t.string "error_code"
    t.datetime "failed_at"
    t.bigint "initiated_by_id"
    t.string "locale", default: "en", null: false
    t.string "provider_reference"
    t.string "public_id", null: false
    t.string "recipient_masked"
    t.datetime "sent_at"
    t.string "status_code", null: false
    t.string "template_code"
    t.datetime "updated_at", null: false
    t.index ["candidate_assignment_id", "channel_code", "created_at"], name: "index_communications_on_assignment_channel_created_at"
    t.index ["candidate_assignment_id"], name: "index_communications_on_candidate_assignment_id"
    t.index ["initiated_by_id"], name: "index_communications_on_initiated_by_id"
    t.index ["provider_reference"], name: "index_communications_on_provider_reference"
    t.index ["public_id"], name: "index_communications_on_public_id", unique: true
    t.check_constraint "channel_code::text ~ '^[a-z0-9_]+$'::text", name: "communications_channel_code_format"
    t.check_constraint "direction_code::text = ANY (ARRAY['inbound'::character varying, 'outbound'::character varying]::text[])", name: "communications_direction_code"
    t.check_constraint "error_code IS NULL OR error_code::text ~ '^[a-z0-9_]+$'::text", name: "communications_error_code_format"
    t.check_constraint "locale::text = ANY (ARRAY['en'::character varying, 'ur'::character varying]::text[])", name: "communications_locale"
    t.check_constraint "status_code::text ~ '^[a-z0-9_]+$'::text", name: "communications_status_code_format"
    t.check_constraint "template_code IS NULL OR template_code::text ~ '^[a-z0-9_]+$'::text", name: "communications_template_code_format"
  end

  create_table "countries", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name_en", null: false
    t.string "name_ur", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_countries_on_code", unique: true
    t.check_constraint "code::text ~ '^[a-z0-9_]+$'::text", name: "countries_code_format"
  end

  create_table "crafts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name_en", null: false
    t.string "name_ur", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_crafts_on_code", unique: true
    t.check_constraint "code::text ~ '^[a-z0-9_]+$'::text", name: "crafts_code_format"
  end

  create_table "document_requirements", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "country_id"
    t.bigint "craft_id"
    t.datetime "created_at", null: false
    t.bigint "document_type_id", null: false
    t.bigint "project_id"
    t.boolean "required", default: true, null: false
    t.datetime "updated_at", null: false
    t.index "document_type_id, COALESCE(country_id, (0)::bigint), COALESCE(project_id, (0)::bigint), COALESCE(craft_id, (0)::bigint)", name: "index_document_requirements_on_unique_scope", unique: true
    t.index ["country_id"], name: "index_document_requirements_on_country_id"
    t.index ["craft_id"], name: "index_document_requirements_on_craft_id"
    t.index ["document_type_id"], name: "index_document_requirements_on_document_type_id"
    t.index ["project_id"], name: "index_document_requirements_on_project_id"
  end

  create_table "document_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name_en", null: false
    t.string "name_ur", null: false
    t.boolean "requires_expiry", default: false, null: false
    t.boolean "requires_number", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_document_types_on_code", unique: true
    t.check_constraint "code::text ~ '^[a-z0-9_]+$'::text", name: "document_types_code_format"
  end

  create_table "idempotency_keys", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "idempotency_scope", null: false
    t.string "key_digest", null: false
    t.string "request_fingerprint", null: false
    t.string "request_method", null: false
    t.string "request_path", null: false
    t.jsonb "response_payload"
    t.integer "response_status"
    t.string "status", default: "processing", null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.index "idempotency_scope, COALESCE(subject_type, '__global__'::character varying), COALESCE(subject_id, (0)::bigint), key_digest", name: "index_idempotency_keys_on_scope_subject_and_key", unique: true
    t.index ["expires_at"], name: "index_idempotency_keys_on_expires_at"
    t.index ["subject_type", "subject_id"], name: "index_idempotency_keys_on_subject"
    t.check_constraint "char_length(key_digest::text) = 64", name: "idempotency_keys_key_digest_length"
    t.check_constraint "request_method::text ~ '^[A-Z]+$'::text", name: "idempotency_keys_request_method_format"
    t.check_constraint "status::text = 'processing'::text AND response_status IS NULL AND response_payload IS NULL AND completed_at IS NULL OR status::text = 'completed'::text AND response_status IS NOT NULL AND response_payload IS NOT NULL AND completed_at IS NOT NULL", name: "idempotency_keys_response_consistency"
    t.check_constraint "status::text = ANY (ARRAY['processing'::character varying, 'completed'::character varying]::text[])", name: "idempotency_keys_status"
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.bigint "candidate_assignment_id", null: false
    t.datetime "created_at", null: false
    t.string "currency_code", null: false
    t.string "external_reference"
    t.text "note"
    t.datetime "paid_at"
    t.string "payment_type_code", null: false
    t.string "public_id", null: false
    t.bigint "recorded_by_id"
    t.string "status_code", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_assignment_id", "status_code", "created_at"], name: "index_payments_on_assignment_status_created_at"
    t.index ["candidate_assignment_id"], name: "index_payments_on_candidate_assignment_id"
    t.index ["external_reference"], name: "index_payments_on_external_reference", unique: true, where: "(external_reference IS NOT NULL)"
    t.index ["public_id"], name: "index_payments_on_public_id", unique: true
    t.index ["recorded_by_id"], name: "index_payments_on_recorded_by_id"
    t.check_constraint "amount > 0::numeric", name: "payments_amount_positive"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "payments_currency_code_format"
    t.check_constraint "payment_type_code::text ~ '^[a-z0-9_]+$'::text", name: "payments_payment_type_code_format"
    t.check_constraint "status_code::text ~ '^[a-z0-9_]+$'::text", name: "payments_status_code_format"
  end

  create_table "permissions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.boolean "system_defined", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_permissions_on_code", unique: true
    t.check_constraint "code::text ~ '^[a-z0-9_]+$'::text", name: "permissions_code_format"
  end

  create_table "projects", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name_en", null: false
    t.string "name_ur", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_projects_on_code", unique: true
    t.check_constraint "code::text ~ '^[a-z0-9_]+$'::text", name: "projects_code_format"
  end

  create_table "refresh_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "replaced_by_id"
    t.datetime "revoked_at"
    t.datetime "rotated_at"
    t.bigint "session_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_refresh_tokens_on_expires_at"
    t.index ["replaced_by_id"], name: "index_refresh_tokens_on_replaced_by_id"
    t.index ["session_id", "revoked_at", "rotated_at", "expires_at"], name: "index_refresh_tokens_on_active_lookup"
    t.index ["session_id"], name: "index_refresh_tokens_on_session_id"
    t.index ["token_digest"], name: "index_refresh_tokens_on_token_digest", unique: true
  end

  create_table "role_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "permission_id", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.boolean "system_defined", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_roles_on_code", unique: true
    t.check_constraint "code::text ~ '^[a-z0-9_]+$'::text", name: "roles_code_format"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "jti", null: false
    t.datetime "last_seen_at"
    t.string "public_id", null: false
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["jti"], name: "index_sessions_on_jti", unique: true
    t.index ["public_id"], name: "index_sessions_on_public_id", unique: true
    t.index ["user_id", "revoked_at"], name: "index_sessions_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "invitation_accepted_at"
    t.datetime "invitation_expires_at"
    t.datetime "invitation_sent_at"
    t.string "invitation_token_digest"
    t.bigint "invited_by_id"
    t.datetime "locked_at"
    t.string "public_id", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "hr", null: false
    t.string "staff_state", default: "active", null: false
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["invitation_token_digest"], name: "index_users_on_invitation_token_digest", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["staff_state"], name: "index_users_on_staff_state"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.check_constraint "staff_state::text = 'active'::text AND active = true OR (staff_state::text = ANY (ARRAY['invited'::character varying, 'suspended'::character varying]::text[])) AND active = false", name: "users_staff_state_matches_active"
    t.check_constraint "staff_state::text = ANY (ARRAY['invited'::character varying, 'active'::character varying, 'suspended'::character varying]::text[])", name: "users_staff_state"
  end

  create_table "workflow_stages", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.boolean "system_defined", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_workflow_stages_on_code", unique: true
    t.index ["position"], name: "index_workflow_stages_on_position", unique: true
    t.check_constraint "code::text ~ '^[a-z0-9_]+$'::text", name: "workflow_stages_code_format"
  end

  add_foreign_key "audit_events", "candidate_assignments"
  add_foreign_key "audit_events", "candidates"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "authentication_events", "sessions"
  add_foreign_key "authentication_events", "users"
  add_foreign_key "candidate_assignments", "candidates"
  add_foreign_key "candidate_assignments", "countries"
  add_foreign_key "candidate_assignments", "crafts"
  add_foreign_key "candidate_assignments", "projects"
  add_foreign_key "candidate_assignments", "users", column: "created_by_id"
  add_foreign_key "candidate_assignments", "workflow_stages", column: "current_workflow_stage_id"
  add_foreign_key "candidate_documents", "candidate_assignments"
  add_foreign_key "candidate_documents", "document_types"
  add_foreign_key "candidate_documents", "users", column: "uploaded_by_id"
  add_foreign_key "candidate_documents", "users", column: "verified_by_id"
  add_foreign_key "candidate_otp_challenges", "candidates"
  add_foreign_key "candidate_refresh_tokens", "candidate_refresh_tokens", column: "replaced_by_id", on_delete: :nullify
  add_foreign_key "candidate_refresh_tokens", "candidate_sessions"
  add_foreign_key "candidate_sessions", "candidates"
  add_foreign_key "candidate_stage_histories", "candidate_assignments"
  add_foreign_key "candidate_stage_histories", "users", column: "actor_id"
  add_foreign_key "candidate_stage_histories", "workflow_stages", column: "from_workflow_stage_id"
  add_foreign_key "candidate_stage_histories", "workflow_stages", column: "to_workflow_stage_id"
  add_foreign_key "candidates", "users", column: "created_by_id"
  add_foreign_key "communications", "candidate_assignments"
  add_foreign_key "communications", "users", column: "initiated_by_id"
  add_foreign_key "document_requirements", "countries"
  add_foreign_key "document_requirements", "crafts"
  add_foreign_key "document_requirements", "document_types"
  add_foreign_key "document_requirements", "projects"
  add_foreign_key "payments", "candidate_assignments"
  add_foreign_key "payments", "users", column: "recorded_by_id"
  add_foreign_key "refresh_tokens", "refresh_tokens", column: "replaced_by_id"
  add_foreign_key "refresh_tokens", "sessions"
  add_foreign_key "role_permissions", "permissions", on_delete: :cascade
  add_foreign_key "role_permissions", "roles", on_delete: :cascade
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "roles", column: "role", primary_key: "code"
  add_foreign_key "users", "users", column: "invited_by_id"
end
