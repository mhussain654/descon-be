# frozen_string_literal: true

class AddReferenceDataAuditConstraints < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :audit_events,
                         "entity_type <> 'ReferenceData' OR metadata ? 'reference_type'",
                         name: 'reference_data_audits_include_type'
  end
end
