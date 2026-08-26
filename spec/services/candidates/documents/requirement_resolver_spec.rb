# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::RequirementResolver do
  describe '.call' do
    it 'returns requirements applicable to the current assignment scope' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      matching_type = create(:document_type, code: 'passport')
      other_type = create(:document_type, code: 'cv')

      matching_requirement = create(
        :document_requirement,
        document_type: matching_type,
        country: assignment.country,
        project: assignment.project,
        craft: assignment.craft
      )
      create(:document_requirement, document_type: other_type, country: create(:country))

      expect(described_class.call(candidate: candidate)).to contain_exactly(matching_requirement)
    end

    it 'prefers the most specific applicable requirement for the same document type' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      document_type = create(:document_type, code: 'passport')
      global_requirement = create(:document_requirement, document_type:, required: true)
      scoped_requirement = create(:document_requirement, document_type:, country: assignment.country, required: false)

      resolved_requirement = described_class.call(candidate: candidate).first

      expect(resolved_requirement).to eq(scoped_requirement)
      expect(resolved_requirement).not_to eq(global_requirement)
    end

    it 'returns an empty list when the candidate has no current assignment' do
      candidate = create(:candidate)

      expect(described_class.call(candidate: candidate)).to eq([])
    end
  end
end
