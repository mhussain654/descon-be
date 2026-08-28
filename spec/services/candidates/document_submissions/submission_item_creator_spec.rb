# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::DocumentSubmissions::SubmissionItemCreator do
  it 'creates immutable submission items from the resolved requirements' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    document_type = create(:document_type, code: "passport_#{SecureRandom.hex(4)}")
    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required: true
    )
    document = create(:candidate_document, candidate_assignment: assignment, document_type:)
    submission = create(:candidate_document_submission, candidate_assignment: assignment)

    described_class.call(
      submission:,
      documents: [document],
      requirements_by_document_type_id: { document_type.id => DocumentRequirement.last }
    )

    expect(submission.submission_items.count).to eq(1)
    expect(submission.submission_items.first).to have_attributes(
      candidate_document: document,
      requirement_code: document_type.code,
      required: true
    )
  end
end
