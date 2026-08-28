# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateDocumentSubmissionItem, type: :model do
  it { is_expected.to belong_to(:candidate_document_submission) }
  it { is_expected.to belong_to(:candidate_document) }

  it 'normalizes requirement_code and validates the required flag' do
    item = build(:candidate_document_submission_item, requirement_code: ' Passport ', required: true)

    expect(item).to be_valid
    expect(item.requirement_code).to eq('passport')

    item.required = nil
    expect(item).not_to be_valid
    expect(item.errors[:required]).to include('is not included in the list')
  end
end
