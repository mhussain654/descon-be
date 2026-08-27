# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateDocumentSubmission, type: :model do
  subject(:submission) { create(:candidate_document_submission) }

  it { is_expected.to belong_to(:candidate_assignment) }

  it 'assigns a public id and normalizes the status code' do
    record = build(:candidate_document_submission, public_id: nil, status_code: ' SUBMITTED ')

    record.validate

    expect(record.public_id).to be_present
    expect(record.status_code).to eq('submitted')
  end

  it 'is immutable once persisted' do
    expect { submission.update!(request_id: 'changed-request-id') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { submission.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
