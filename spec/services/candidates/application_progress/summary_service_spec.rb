# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::ApplicationProgress::SummaryService do
  def existing_or_create_document_type(code, name_en: code.humanize, name_ur: code.humanize)
    DocumentType.find_or_create_by!(code:) do |document_type|
      document_type.name_en = name_en
      document_type.name_ur = name_ur
      document_type.active = true
      document_type.requires_number = false
      document_type.requires_expiry = false
    end
  end

  def create_requirement(assignment:, code:, required: true)
    document_type = existing_or_create_document_type(code)
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

  describe '.call' do
    it 'returns no_assignment when the candidate has no assignment' do
      progress = described_class.call(candidate: create(:candidate))

      expect(progress.documents.submission_state).to eq('no_assignment')
      expect(progress.documents.required_total).to eq(0)
      expect(progress.documents.can_submit).to be(false)
    end

    it 'returns no_requirements when the assignment has no required documents' do
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)

      progress = described_class.call(candidate:)

      expect(progress.documents.submission_state).to eq('no_requirements')
      expect(progress.documents.completion_percentage).to eq(0)
    end

    it 'returns ready when all required documents are present and at least one is uploaded' do
      candidate = create(:candidate, preferred_locale: 'ur')
      assignment = create(:candidate_assignment, candidate:)
      passport = create_requirement(assignment:, code: 'passport')
      cv = create_requirement(assignment:, code: 'cv')

      create(:candidate_document, candidate_assignment: assignment, document_type: passport, status_code: 'uploaded')
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: cv,
        status_code: 'verified',
        verified_by: create(:user),
        verified_at: Time.current,
        rejection_reason: nil
      )

      progress = described_class.call(candidate:)

      expect(progress.documents.submission_state).to eq('ready')
      expect(progress.documents.required_total).to eq(2)
      expect(progress.documents.submitted_total).to eq(2)
      expect(progress.documents.completion_percentage).to eq(100)
      expect(progress.documents.can_submit).to be(true)
    end

    it 'ignores optional requirements when calculating readiness' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      create_requirement(assignment:, code: 'passport', required: true)
      optional_type = create_requirement(assignment:, code: 'cv', required: false)
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: optional_type,
        status_code: 'uploaded'
      )

      progress = described_class.call(candidate:)

      expect(progress.documents.required_total).to eq(1)
      expect(progress.documents.missing).to eq(1)
      expect(progress.documents.submission_state).to eq('incomplete')
    end

    it 'reports blocking requirements for missing and rejected required documents' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      missing_type = create_requirement(assignment:, code: 'passport')
      rejected_type = create_requirement(assignment:, code: 'cv')
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: rejected_type,
        status_code: 'rejected',
        verified_by: create(:user),
        verified_at: Time.current,
        rejection_reason: 'blurred'
      )

      progress = described_class.call(candidate:)

      expect(progress.documents.submission_state).to eq('changes_required')
      expect(progress.documents.blocking_requirements.map(&:requirement_code)).to contain_exactly('passport', 'cv')
      expect(
        progress.documents.blocking_requirements.find { |item| item.requirement_code == missing_type.code }.reason
      ).to eq('missing')
      expect(
        progress.documents.blocking_requirements.find { |item| item.requirement_code == rejected_type.code }.reason
      ).to eq('rejected')
    end

    it 'reports submitted and partially_verified states from current document statuses' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      passport = create_requirement(assignment:, code: 'passport')
      cv = create_requirement(assignment:, code: 'cv')

      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: passport,
        status_code: 'under_verification'
      )
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: cv,
        status_code: 'verified',
        verified_by: create(:user),
        verified_at: Time.current
      )

      progress = described_class.call(candidate:)
      expect(progress.documents.submission_state).to eq('partially_verified')

      CandidateDocument.find_by!(candidate_assignment: assignment, document_type: cv).destroy
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: cv,
        status_code: 'under_verification'
      )

      progress = described_class.call(candidate:)
      expect(progress.documents.submission_state).to eq('submitted')
      expect(progress.documents.can_submit).to be(false)
    end
  end
end
