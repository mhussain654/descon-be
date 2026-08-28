# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::DocumentSubmissionPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  it 'allows only roles with active manage_candidate_documents permission' do
    %w[admin hr mps].each do |role|
      expect(described_class.new(create(:user, role:), CandidateDocumentSubmission).index?).to be(true)
    end

    %w[finance management].each do |role|
      expect(described_class.new(create(:user, role:), CandidateDocumentSubmission).index?).to be(false)
    end
  end

  it 'denies inactive users, inactive roles, and inactive permissions' do
    actor = create(:user, role: 'admin')
    actor.update!(active: false)
    expect(described_class.new(actor, CandidateDocumentSubmission).index?).to be(false)

    actor = create(:user, role: 'admin')
    actor.staff_role.update!(active: false)
    expect(described_class.new(actor, CandidateDocumentSubmission).index?).to be(false)

    Permission.find_by!(code: 'manage_candidate_documents').update!(active: false)
    expect(described_class.new(create(:user, role: 'admin'), CandidateDocumentSubmission).index?).to be(false)
  end
end
