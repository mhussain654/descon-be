# frozen_string_literal: true

class SeedWorkflowStages < ActiveRecord::Migration[8.1]
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
    now = connection.quote(Time.current)

    execute <<~SQL.squish
      INSERT INTO workflow_stages (code, position, system_defined, active, created_at, updated_at)
      VALUES #{CANONICAL_WORKFLOW_STAGES.map { |stage| values_for(stage, now) }.join(', ')}
      ON CONFLICT (code) DO NOTHING
    SQL
  end

  def down
    execute <<~SQL.squish
      DELETE FROM workflow_stages
      WHERE code IN (#{CANONICAL_WORKFLOW_STAGES.map { |stage| connection.quote(stage.fetch(:code)) }.join(', ')})
    SQL
  end

  private

  def values_for(stage, now)
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
