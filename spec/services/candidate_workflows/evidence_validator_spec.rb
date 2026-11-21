# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::EvidenceValidator do
  before { ensure_canonical_workflow_stages! }

  let(:mobilized_stage) { WorkflowStage.find_by!(code: 'mobilized') }

  describe 'the mobilization date' do
    it 'accepts today in Pakistan' do
      expect do
        described_class.call(destination_stage: mobilized_stage,
                             evidence: { 'mobilized_on' => CandidateFlightDetail.pakistan_today.iso8601 })
      end.not_to raise_error
    end

    it 'refuses a date later than today, on every transition path' do
      expect do
        described_class.call(destination_stage: mobilized_stage,
                             evidence: { 'mobilized_on' => (CandidateFlightDetail.pakistan_today + 1).iso8601 })
      end.to raise_error(ValidationError) { |error|
        expect(error.field).to eq('candidate_workflow_transition.evidence.mobilized_on')
      }
    end
  end
end
