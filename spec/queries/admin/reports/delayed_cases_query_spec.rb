# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::DelayedCasesQuery do
  def stage(code, position)
    WorkflowStage.find_or_create_by!(code:) do |record|
      record.position = position
      record.system_defined = true
    end
  end

  let(:now) { Time.zone.parse('2026-06-15 12:00:00') }
  let(:verified_stage) { stage('verified', 5) }
  let(:mobilized_stage) { stage('mobilized', 15) }

  it 'counts a candidate as delayed/critical using their most recent transition into the current stage' do
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: 30.days.ago(now))
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                     occurred_at: now - 10.days)

    result = described_class.call(reference_time: now)

    expect(result).to eq(delayed: 1, critical: 0)
  end

  it 'falls back to the assignment created_at when no stage-history row exists yet' do
    create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: now - 20.days)

    result = described_class.call(reference_time: now)

    expect(result).to eq(delayed: 1, critical: 1)
  end

  it 'excludes candidates below the threshold' do
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: 30.days.ago(now))
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                     occurred_at: now - 2.days)

    expect(described_class.call(reference_time: now)).to eq(delayed: 0, critical: 0)
  end

  it 'excludes candidates who already reached the terminal mobilized stage' do
    assignment = create(:candidate_assignment, current_workflow_stage: mobilized_stage, created_at: now - 30.days)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: mobilized_stage,
                                     occurred_at: now - 20.days)

    expect(described_class.call(reference_time: now)).to eq(delayed: 0, critical: 0)
  end

  it 'counts critical cases within delayed as well' do
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: 40.days.ago(now))
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                     occurred_at: now - 20.days)

    expect(described_class.call(reference_time: now)).to eq(delayed: 1, critical: 1)
  end

  it 'returns a bounded oldest-first work queue using the same stage-entry age and scope as totals' do
    old = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: now - 30.days)
    recent = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: now - 40.days)
    create(:candidate_stage_history, candidate_assignment: recent, to_workflow_stage: verified_stage,
                                     occurred_at: now - 10.days)
    query = described_class.new(reference_time: now)

    expect(query.attention_candidates).to contain_exactly(
      hash_including(candidate_public_id: old.candidate.public_id, days_waiting: 30, severity: 'critical'),
      hash_including(candidate_public_id: recent.candidate.public_id, days_waiting: 10, severity: 'delayed')
    )
    expect(query.attention_candidates.first.fetch(:candidate_public_id)).to eq(old.candidate.public_id)
    scoped = described_class.new(reference_time: now, scope: Candidate.where(id: recent.candidate_id))
    expect(scoped.attention_candidates.map { |row| row.fetch(:candidate_public_id) }).to eq([recent.candidate.public_id])
  end

  it 'limits attention rows and excludes terminal and recently moved cases' do
    9.times { create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: now - 20.days) }
    create(:candidate_assignment, current_workflow_stage: mobilized_stage, created_at: now - 30.days)
    create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: now - 1.day)

    expect(described_class.new(reference_time: now).attention_candidates.size).to eq(8)
  end

  describe 'stage re-entry robustness' do
    # A security review flagged that joining every candidate_stage_histories
    # row matching (candidate_assignment_id, to_workflow_stage_id) and
    # calling .count could double-count an assignment that re-entered the
    # same stage more than once. Verified against the real schema: a unique
    # index (index_stage_histories_on_assignment_and_destination_stage,
    # scope: [candidate_assignment_id, to_workflow_stage_id]) makes that
    # actually impossible today -- attempting to create a second history row
    # for the same assignment+stage raises ActiveRecord::RecordNotUnique, so
    # there is no realistic multi-row-per-assignment scenario to reproduce.
    # The query was still hardened to select only the single latest matching
    # entry via a LATERAL join and to `.distinct.count` explicitly, as
    # defense in depth against that constraint ever being relaxed -- this
    # spec exists to document why a fan-out reproduction isn't included.
    it 'still returns exactly one candidate per non-terminal assignment (the ordinary, non-re-entrant case)' do
      assignment = create(:candidate_assignment, current_workflow_stage: verified_stage, created_at: 40.days.ago(now))
      create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage,
                                       occurred_at: now - 10.days)

      expect(described_class.call(reference_time: now)).to eq(delayed: 1, critical: 0)
    end
  end

  describe 'configurable thresholds' do
    it 'reads DASHBOARD_DELAYED_THRESHOLD_DAYS/DASHBOARD_CRITICAL_THRESHOLD_DAYS at load time' do
      expect(described_class::DELAYED_THRESHOLD).to eq(ENV.fetch('DASHBOARD_DELAYED_THRESHOLD_DAYS', '7').to_i.days)
      expect(described_class::CRITICAL_THRESHOLD).to eq(ENV.fetch('DASHBOARD_CRITICAL_THRESHOLD_DAYS', '14').to_i.days)
    end
  end
end
