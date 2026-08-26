# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::RequirementResolver do
  def existing_or_create_document_type(code)
    DocumentType.find_or_create_by!(code:) do |document_type|
      document_type.name_en = code.humanize
      document_type.name_ur = code.humanize
      document_type.active = true
      document_type.requires_number = false
      document_type.requires_expiry = false
    end
  end

  describe '.call' do
    it 'returns requirements applicable to the current assignment scope' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      matching_type = existing_or_create_document_type('passport')
      other_type = existing_or_create_document_type('cv')

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
      document_type = existing_or_create_document_type('passport')
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
