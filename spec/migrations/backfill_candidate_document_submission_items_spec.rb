# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260828090000_backfill_candidate_document_submission_items')

RSpec.describe BackfillCandidateDocumentSubmissionItems do
  subject(:migration) { described_class.new }

  let(:assignment) { create(:candidate_assignment) }

  def create_requirement(code)
    document_type = create(:document_type, code:)

    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required: true
    )

    document_type
  end

  def create_submission(submitted_at:)
    create(
      :candidate_document_submission,
      candidate_assignment: assignment,
      submitted_at:,
      created_at: submitted_at,
      updated_at: submitted_at
    )
  end

  def create_document(document_type:, uploaded_at:, superseded_at: nil, status_code: 'uploaded')
    create(:candidate_document, **base_document_attributes(document_type:, uploaded_at:, superseded_at:, status_code:))
  end

  def base_document_attributes(document_type:, uploaded_at:, superseded_at:, status_code:)
    {
      candidate_assignment: assignment,
      document_type:,
      uploaded_at:,
      created_at: uploaded_at,
      updated_at: uploaded_at,
      superseded_at:,
      status_code:
    }.merge(review_attributes_for(status_code, uploaded_at))
  end

  def review_attributes_for(status_code, uploaded_at)
    return {} unless status_code == 'rejected'

    reviewer = create(:user, role: 'admin')

    {
      verified_by: reviewer,
      verified_at: uploaded_at + 1.hour,
      rejection_reason: 'Document is unreadable.'
    }
  end

  describe '#up' do
    it 'backfills one legacy submission with the document that was current when it was submitted' do
      passport = create_requirement("passport_#{SecureRandom.hex(4)}")
      document = create_document(document_type: passport, uploaded_at: Time.zone.parse('2026-08-20 09:00:00'))
      submission = create_submission(submitted_at: Time.zone.parse('2026-08-20 10:00:00'))

      expect { migration.up }.to change(CandidateDocumentSubmissionItem, :count).by(1)

      expect(submission.reload.submission_items.first).to have_attributes(
        candidate_document: document,
        requirement_code: passport.code,
        required: true
      )
    end

    it 'assigns the superseded document to the earlier submission and the replacement to the later submission' do
      passport = create_requirement("passport_#{SecureRandom.hex(4)}")
      original_document = create_document(
        document_type: passport,
        uploaded_at: Time.zone.parse('2026-08-20 09:00:00'),
        superseded_at: Time.zone.parse('2026-08-22 09:00:00'),
        status_code: 'rejected'
      )
      replacement_document = create_document(
        document_type: passport,
        uploaded_at: Time.zone.parse('2026-08-22 09:00:00')
      )
      first_submission = create_submission(submitted_at: Time.zone.parse('2026-08-20 10:00:00'))
      second_submission = create_submission(submitted_at: Time.zone.parse('2026-08-22 10:00:00'))

      migration.up

      expect(first_submission.reload.submission_items.first.candidate_document).to eq(original_document)
      expect(second_submission.reload.submission_items.first.candidate_document).to eq(replacement_document)
    end

    it 'is safe to rerun and recovers a partial backfill by creating only missing submission items' do
      passport = create_requirement("passport_#{SecureRandom.hex(4)}")
      visa = create_requirement("visa_#{SecureRandom.hex(4)}")
      passport_document = create_document(document_type: passport, uploaded_at: Time.zone.parse('2026-08-20 09:00:00'))
      visa_document = create_document(document_type: visa, uploaded_at: Time.zone.parse('2026-08-20 09:05:00'))
      submission = create_submission(submitted_at: Time.zone.parse('2026-08-20 10:00:00'))

      create(
        :candidate_document_submission_item,
        candidate_document_submission: submission,
        candidate_document: passport_document,
        requirement_code: passport.code,
        required: true
      )

      expect { migration.up }.to change(CandidateDocumentSubmissionItem, :count).by(1)

      submission.reload
      expect(submission.submission_items.order(:requirement_code).pluck(:requirement_code)).to eq(
        [passport.code, visa.code].sort
      )
      expect(submission.submission_items.find_by!(requirement_code: visa.code).candidate_document).to eq(visa_document)

      expect { migration.up }.not_to change(CandidateDocumentSubmissionItem, :count)
    end
  end
end
