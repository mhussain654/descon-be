# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::DocumentSubmissions::ProgressSummaryBuilder do
  def create_requirement(assignment:, code:, required: true)
    document_type = create(:document_type, code:)
    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required:
    )
    document_type
  end

  it 'delegates to the application progress summary using the provided submission context' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    passport = create_requirement(assignment:, code: "passport_#{SecureRandom.hex(4)}")
    document = create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type: passport,
      status_code: 'uploaded'
    )
    current_documents_by_type = { passport.id => document }
    requirements = Candidates::Documents::RequirementResolver.call(candidate:, assignment:)

    summary = described_class.call(
      candidate:,
      assignment:,
      current_documents_by_type:,
      requirements:
    )

    expect(summary.documents.required_total).to eq(1)
    expect(summary.documents.uploaded).to eq(1)
    expect(summary.documents.submission_state).to eq('ready')
  end
end
