# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateAiCall, type: :model do
  subject(:candidate_ai_call) { build(:candidate_ai_call) }

  it { is_expected.to belong_to(:communication) }
  it { is_expected.to belong_to(:candidate).optional }
  it { is_expected.to belong_to(:candidate_assignment).optional }
  it { is_expected.to belong_to(:triggered_by).class_name('User').optional }
  it { is_expected.to belong_to(:reviewed_by).class_name('User').optional }
  it { is_expected.to have_many(:candidate_ai_call_events).dependent(:restrict_with_exception) }
  it { is_expected.to have_one(:candidate_ai_call_transcript).dependent(:restrict_with_exception) }

  it 'assigns a public_id on create' do
    candidate_ai_call.public_id = nil

    candidate_ai_call.save!

    expect(candidate_ai_call.public_id).to be_present
  end

  it 'defaults status, provider_code and verification_status when blank' do
    candidate_ai_call.status = nil
    candidate_ai_call.provider_code = nil
    candidate_ai_call.verification_status = nil

    candidate_ai_call.validate

    expect(candidate_ai_call.status).to eq('requested')
    expect(candidate_ai_call.provider_code).to eq('elevenlabs')
    expect(candidate_ai_call.verification_status).to eq('not_applicable')
  end

  it 'normalizes code-like attributes' do
    candidate_ai_call.direction = ' OUTBOUND '
    candidate_ai_call.call_reason = ' Missing_Documents '
    candidate_ai_call.outcome = ' ANSWERED '
    candidate_ai_call.outcome_reason = ' Resolved '

    candidate_ai_call.validate

    expect(candidate_ai_call.direction).to eq('outbound')
    expect(candidate_ai_call.call_reason).to eq('missing_documents')
    expect(candidate_ai_call.outcome).to eq('answered')
    expect(candidate_ai_call.outcome_reason).to eq('resolved')
  end

  it 'rejects an unsupported direction' do
    candidate_ai_call.direction = 'sideways'

    expect(candidate_ai_call).not_to be_valid
    expect(candidate_ai_call.errors[:direction]).to be_present
  end

  it 'rejects an unsupported outcome' do
    candidate_ai_call.outcome = 'maybe'

    expect(candidate_ai_call).not_to be_valid
  end

  it 'allows a nil outcome (unresolved calls)' do
    candidate_ai_call.outcome = nil

    expect(candidate_ai_call).to be_valid
  end

  it 'keeps candidate and assignment references consistent' do
    assignment = create(:candidate_assignment)
    candidate_ai_call.candidate = create(:candidate)
    candidate_ai_call.candidate_assignment = assignment

    expect(candidate_ai_call).not_to be_valid
    expect(candidate_ai_call.errors[:candidate_assignment]).to include('is invalid')
  end

  it 'allows a matching candidate and assignment pair' do
    assignment = create(:candidate_assignment)
    candidate_ai_call.candidate = assignment.candidate
    candidate_ai_call.candidate_assignment = assignment

    expect(candidate_ai_call).to be_valid
  end

  it 'requires extracted_data to be present (defaults to an empty hash)' do
    candidate_ai_call.extracted_data = nil

    expect(candidate_ai_call).not_to be_valid
    expect(candidate_ai_call.errors[:extracted_data]).to be_present
  end

  describe 'workflow_stage_code / call_reason consistency' do
    it 'requires workflow_stage_code when call_reason is workflow_stage_notification' do
      candidate_ai_call.call_reason = 'workflow_stage_notification'
      candidate_ai_call.workflow_stage_code = nil

      expect(candidate_ai_call).not_to be_valid
      expect(candidate_ai_call.errors[:workflow_stage_code]).to be_present
    end

    it 'is valid with a workflow_stage_code when call_reason is workflow_stage_notification' do
      candidate_ai_call.call_reason = 'workflow_stage_notification'
      candidate_ai_call.workflow_stage_code = 'verified'

      expect(candidate_ai_call).to be_valid
    end

    it 'rejects a workflow_stage_code for any other call_reason' do
      candidate_ai_call.call_reason = 'missing_documents'
      candidate_ai_call.workflow_stage_code = 'verified'

      expect(candidate_ai_call).not_to be_valid
      expect(candidate_ai_call.errors[:workflow_stage_code]).to be_present
    end
  end

  describe '#terminal_status?' do
    it 'is true for completed, failed and cancelled statuses' do
      %w[completed failed cancelled].each do |status|
        candidate_ai_call.status = status
        expect(candidate_ai_call).to be_terminal_status
      end
    end

    it 'is false for in-flight statuses' do
      %w[requested queued ringing in_progress processing].each do |status|
        candidate_ai_call.status = status
        expect(candidate_ai_call).not_to be_terminal_status
      end
    end
  end

  describe '#needs_manual_review?' do
    it 'is true only when outcome is nil and outcome_reason is needs_manual_review' do
      reviewable = build(:candidate_ai_call, :needs_manual_review)
      resolved = build(:candidate_ai_call, :answered)

      expect(reviewable).to be_needs_manual_review
      expect(resolved).not_to be_needs_manual_review
    end
  end

  describe '.awaiting_review' do
    it 'returns only unreviewed manual-review calls' do
      pending_review = create(:candidate_ai_call, :needs_manual_review)
      create(:candidate_ai_call, :needs_manual_review, reviewed_at: Time.current)
      create(:candidate_ai_call, :answered)

      expect(described_class.awaiting_review).to contain_exactly(pending_review)
    end
  end
end
