# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetMissingDocuments do
  it 'returns the missing-documents summary' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:,
                                                       candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result).to have_key(:missing_count)
    expect(result).to have_key(:blocking_requirements)
  end

  it 'serializes each blocking requirement when documents are still missing' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    document_type = create(:document_type)
    create(:document_requirement, document_type:, country: assignment.country, project: assignment.project,
                                  craft: assignment.craft, required: true)
    call_record = create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:,
                                                       candidate_assignment: assignment)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:missing_count]).to be >= 1
    requirement = result[:blocking_requirements].find { |r| r[:requirement_code] == document_type.code }
    expect(requirement).to include(:requirement_code, :name, :reason)
    expect(requirement[:reason]).to eq('missing')
  end
end
