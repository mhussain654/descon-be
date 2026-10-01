# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::PendingActionsQuery do
  describe 'overdue_qvc_count' do
    it 'counts an open QVC attempt whose appointment date has already passed' do
      assignment = create(:candidate_assignment)
      create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: 2.days.ago)

      expect(described_class.call.fetch(:overdue_qvc_count)).to eq(1)
    end

    it 'excludes a QVC attempt whose appointment date is still upcoming' do
      assignment = create(:candidate_assignment)
      create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: 2.days.from_now)

      expect(described_class.call.fetch(:overdue_qvc_count)).to eq(0)
    end

    it 'excludes a QVC attempt that already has a recorded outcome, even if its appointment date is in the past' do
      assignment = create(:candidate_assignment)
      create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: 2.days.ago,
                                     outcome_code: 'approved', outcome_recorded_at: 1.day.ago,
                                     outcome_recorded_by: create(:user))

      expect(described_class.call.fetch(:overdue_qvc_count)).to eq(0)
    end
  end

  describe 'callback_required_count' do
    it 'counts a recently-completed call with a callback_required outcome' do
      assignment = create(:candidate_assignment)
      create(:candidate_ai_call, candidate: assignment.candidate, candidate_assignment: assignment,
                                 outcome: 'callback_required', completed_at: 1.day.ago)

      expect(described_class.call.fetch(:callback_required_count)).to eq(1)
    end

    it 'excludes a call older than the 30-day lookback window' do
      assignment = create(:candidate_assignment)
      create(:candidate_ai_call, candidate: assignment.candidate, candidate_assignment: assignment,
                                 outcome: 'callback_required', completed_at: 40.days.ago)

      expect(described_class.call.fetch(:callback_required_count)).to eq(0)
    end

    it 'excludes a call with a different outcome' do
      assignment = create(:candidate_assignment)
      create(:candidate_ai_call, candidate: assignment.candidate, candidate_assignment: assignment,
                                 outcome: 'answered', completed_at: 1.day.ago)

      expect(described_class.call.fetch(:callback_required_count)).to eq(0)
    end
  end

  it 'only considers candidates within the given scope' do
    active_assignment = create(:candidate_assignment, candidate: create(:candidate, active: true))
    create(:candidate_qvc_attempt, candidate_assignment: active_assignment, appointment_date: 2.days.ago)

    inactive_assignment = create(:candidate_assignment, candidate: create(:candidate, active: false))
    create(:candidate_qvc_attempt, candidate_assignment: inactive_assignment, appointment_date: 2.days.ago)

    expect(described_class.call(scope: Candidate.active).fetch(:overdue_qvc_count)).to eq(1)
  end
end
