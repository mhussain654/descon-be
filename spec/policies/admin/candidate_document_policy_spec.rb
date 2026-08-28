# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateDocumentPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  it 'allows access, verify, and reject only for roles with active manage_candidate_documents permission' do
    document = create(:candidate_document)

    %w[admin hr mps].each do |role|
      policy = described_class.new(create(:user, role:), document)
      expect(policy.access?).to be(true)
      expect(policy.verify?).to be(true)
      expect(policy.reject?).to be(true)
    end

    %w[finance management].each do |role|
      policy = described_class.new(create(:user, role:), document)
      expect(policy.access?).to be(false)
      expect(policy.verify?).to be(false)
      expect(policy.reject?).to be(false)
    end
  end

  it 'scopes to current submitted documents only' do
    submitted_document = create(:candidate_document, status_code: 'under_verification')
    create(:candidate_document_submission_item, candidate_document: submitted_document)
    non_current_document = create(:candidate_document, status_code: 'under_verification', superseded_at: Time.current)
    create(:candidate_document_submission_item, candidate_document: non_current_document)
    unsubmitted_document = create(:candidate_document, status_code: 'under_verification')
    actor = create(:user, role: 'admin')

    scoped_documents = described_class::Scope.new(actor, CandidateDocument.all).resolve

    expect(scoped_documents).to include(submitted_document)
    expect(scoped_documents).not_to include(non_current_document)
    expect(scoped_documents).not_to include(unsubmitted_document)
  end
end
