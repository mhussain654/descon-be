# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::QvcAttemptQuery do
  it 'returns attempts in attempt order and can filter no-shows' do
    assignment = create(:candidate_assignment)
    actor = create(:user)
    approved_attempt = create(
      :candidate_qvc_attempt,
      candidate_assignment: assignment,
      scheduled_by: actor,
      attempt_number: 2,
      appointment_date: Date.new(2026, 9, 2),
      outcome_code: 'approved',
      outcome_recorded_at: Time.zone.parse('2026-09-02T10:00:00Z'),
      outcome_recorded_by: actor
    )
    no_show_attempt = create(
      :candidate_qvc_attempt,
      candidate_assignment: assignment,
      scheduled_by: actor,
      attempt_number: 1,
      appointment_date: Date.new(2026, 9, 1),
      no_show: true,
      outcome_recorded_at: Time.zone.parse('2026-09-01T10:00:00Z'),
      outcome_recorded_by: actor
    )

    attempts = described_class.call(scope: assignment.candidate_qvc_attempts)
    no_shows = described_class.call(scope: assignment.candidate_qvc_attempts, no_show_only: true)

    expect(attempts).to eq([no_show_attempt, approved_attempt])
    expect(no_shows).to eq([no_show_attempt])
  end
end
