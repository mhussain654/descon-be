# frozen_string_literal: true

class AddCoreRelationalConstraints < ActiveRecord::Migration[8.1]
  CODE_FORMAT_SQL = '^[a-z0-9_]+$'

  def change
    add_candidate_constraints
    add_candidate_assignment_constraints
    add_candidate_stage_history_constraints
    add_candidate_document_constraints
    add_payment_constraints
    add_communication_constraints
    add_audit_event_constraints
  end

  private

  def add_candidate_constraints
    add_check_constraint :candidates, "cnic ~ '^\\d{5}-\\d{7}-\\d$'", name: 'candidates_cnic_format'
    add_check_constraint :candidates, "mobile_number ~ '^\\+?\\d{10,15}$'", name: 'candidates_mobile_number_format'
    add_check_constraint :candidates, "preferred_locale IN ('en', 'ur')", name: 'candidates_preferred_locale'
    add_check_constraint :candidates, "source_code IN ('admin_ui', 'csv_import')", name: 'candidates_source_code'
  end

  def add_candidate_assignment_constraints
    add_check_constraint :candidate_assignments,
                         "qvc_outcome_code IS NULL OR qvc_outcome_code ~ '#{CODE_FORMAT_SQL}'",
                         name: 'candidate_assignments_qvc_outcome_code_format'
    add_check_constraint :candidate_assignments,
                         qvc_pair_constraint_sql,
                         name: 'candidate_assignments_qvc_pair'
  end

  def add_candidate_stage_history_constraints
    add_check_constraint :candidate_stage_histories,
                         "reason_code IS NULL OR reason_code ~ '#{CODE_FORMAT_SQL}'",
                         name: 'candidate_stage_histories_reason_code_format'
    add_check_constraint :candidate_stage_histories,
                         '(from_workflow_stage_id IS NULL OR from_workflow_stage_id <> to_workflow_stage_id)',
                         name: 'candidate_stage_histories_distinct_transition'
  end

  def add_candidate_document_constraints
    add_check_constraint :candidate_documents,
                         "status_code IN ('uploaded', 'under_verification', 'verified', 'rejected')",
                         name: 'candidate_documents_status_code'
    add_check_constraint :candidate_documents,
                         candidate_document_state_sql,
                         name: 'candidate_documents_status_consistency'
  end

  def add_payment_constraints
    add_check_constraint :payments,
                         "payment_type_code ~ '#{CODE_FORMAT_SQL}'",
                         name: 'payments_payment_type_code_format'
    add_check_constraint :payments, "status_code ~ '#{CODE_FORMAT_SQL}'", name: 'payments_status_code_format'
    add_check_constraint :payments, 'amount > 0', name: 'payments_amount_positive'
    add_check_constraint :payments, "currency_code ~ '^[A-Z]{3}$'", name: 'payments_currency_code_format'
  end

  def add_communication_constraints
    add_check_constraint :communications,
                         "channel_code ~ '#{CODE_FORMAT_SQL}'",
                         name: 'communications_channel_code_format'
    add_check_constraint :communications,
                         "direction_code IN ('inbound', 'outbound')",
                         name: 'communications_direction_code'
    add_check_constraint :communications,
                         "status_code ~ '#{CODE_FORMAT_SQL}'",
                         name: 'communications_status_code_format'
    add_check_constraint :communications,
                         "template_code IS NULL OR template_code ~ '#{CODE_FORMAT_SQL}'",
                         name: 'communications_template_code_format'
    add_check_constraint :communications,
                         "error_code IS NULL OR error_code ~ '#{CODE_FORMAT_SQL}'",
                         name: 'communications_error_code_format'
    add_check_constraint :communications, "locale IN ('en', 'ur')", name: 'communications_locale'
  end

  def add_audit_event_constraints
    add_check_constraint :audit_events, "action_code ~ '#{CODE_FORMAT_SQL}'", name: 'audit_events_action_code_format'
    add_check_constraint :audit_events,
                         "reason_code IS NULL OR reason_code ~ '#{CODE_FORMAT_SQL}'",
                         name: 'audit_events_reason_code_format'
  end

  def qvc_pair_constraint_sql
    <<~SQL.squish
      (
        (qvc_outcome_code IS NULL AND qvc_outcome_date IS NULL) OR
        (qvc_outcome_code IS NOT NULL AND qvc_outcome_date IS NOT NULL)
      )
    SQL
  end

  def candidate_document_state_sql
    <<~SQL.squish
      (
        (
          status_code IN ('uploaded', 'under_verification') AND
          verified_by_id IS NULL AND
          verified_at IS NULL AND
          rejection_reason IS NULL
        ) OR
        (
          status_code = 'verified' AND
          verified_by_id IS NOT NULL AND
          verified_at IS NOT NULL AND
          rejection_reason IS NULL
        ) OR
        (
          status_code = 'rejected' AND
          verified_by_id IS NOT NULL AND
          verified_at IS NOT NULL AND
          rejection_reason IS NOT NULL
        )
      )
    SQL
  end
end
