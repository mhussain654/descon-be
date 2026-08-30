# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::DocumentSubmissions::SubmitService do
  self.use_transactional_tests = false

  around do |example|
    CandidateDocumentSubmissionItem.delete_all
    CandidateDocumentSubmission.delete_all
    AuditEvent.delete_all
    CandidateDocument.delete_all
    CandidateAssignment.delete_all
    Candidate.delete_all
    User.delete_all
    example.run
  ensure
    CandidateDocumentSubmissionItem.delete_all
    CandidateDocumentSubmission.delete_all
    AuditEvent.delete_all
    CandidateDocument.delete_all
    CandidateAssignment.delete_all
    Candidate.delete_all
    User.delete_all
  end

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

  def resolved_required_requirements(candidate:, assignment:)
    Candidates::Documents::RequirementResolver.call(candidate:, assignment:).select(&:required)
  end

  def create_required_documents(candidate:, assignment:, default_status:, overrides: {})
    resolved_required_requirements(candidate:, assignment:).each do |requirement|
      create_required_document(
        assignment:,
        requirement:,
        default_status:,
        overrides: overrides.fetch(requirement.document_type.code, {})
      )
    end
  end

  def create_required_document(assignment:, requirement:, default_status:, overrides:)
    override_attributes = overrides.dup
    return if override_attributes.delete(:skip_create)

    status_code = override_attributes.fetch(:status_code, default_status)
    attributes = {
      candidate_assignment: assignment,
      document_type: requirement.document_type,
      status_code:
    }.merge(default_status_attributes_for(status_code)).merge(override_attributes)

    create(:candidate_document, **attributes)
  end

  def default_status_attributes_for(status_code)
    case status_code
    when 'verified'
      { verified_by: create(:user), verified_at: Time.current }
    when 'rejected'
      { verified_by: create(:user), verified_at: Time.current, rejection_reason: 'blurred' }
    else
      {}
    end
  end

  def blocking_requirement_for(error, requirement_code)
    error.details[:blocking_requirements].find do |requirement|
      requirement[:requirement_code] == requirement_code
    end
  end

  describe '.call' do
    it 'submits uploaded documents atomically and creates immutable evidence' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      passport = create_requirement(assignment:, code: 'passport')
      cv = create_requirement(assignment:, code: 'cv', required: false)
      create_required_documents(
        candidate:,
        assignment:,
        default_status: 'verified',
        overrides: {
          'passport' => { document_type: passport, status_code: 'uploaded' }
        }
      )
      create(:candidate_document, candidate_assignment: assignment, document_type: cv, status_code: 'uploaded')

      result = described_class.call(candidate:, request_id: 'candidate-submit-1')

      expect(result.submission_state).to eq('submitted')
      expect(result.documents[:pending_review]).to eq(1)
      expect(result.documents[:can_submit]).to be(false)
      expect(CandidateDocumentSubmission.count).to eq(1)
      expect(CandidateDocumentSubmissionItem.count).to eq(2)
      expect(
        CandidateDocument.current_version.find_by!(
          candidate_assignment: assignment,
          document_type: passport
        ).status_code
      ).to eq('under_verification')
      expect(
        CandidateDocument.current_version.find_by!(
          candidate_assignment: assignment,
          document_type: cv
        ).status_code
      ).to eq('under_verification')
      expect(AuditEvent.last.action_code).to eq('candidate_documents_submitted')
    end

    it 'does not change data when a required document is missing' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      create_requirement(assignment:, code: 'passport')
      create_required_documents(
        candidate:,
        assignment:,
        default_status: 'verified',
        overrides: {
          'passport' => { skip_create: true }
        }
      )

      expect do
        described_class.call(candidate:, request_id: 'candidate-submit-2')
      end.to raise_error(DocumentsIncompleteError) { |error|
        expect(blocking_requirement_for(error, 'passport')&.fetch(:reason)).to eq('missing')
      }

      expect(CandidateDocumentSubmission.count).to eq(0)
      expect(AuditEvent.count).to eq(0)
    end

    it 'blocks rejected required documents until they are replaced' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      passport = create_requirement(assignment:, code: 'passport')
      create_required_documents(
        candidate:,
        assignment:,
        default_status: 'verified',
        overrides: {
          'passport' => {
            document_type: passport,
            status_code: 'rejected'
          }
        }
      )

      expect do
        described_class.call(candidate:, request_id: 'candidate-submit-3')
      end.to raise_error(DocumentsRejectedError) { |error|
        expect(blocking_requirement_for(error, 'passport')&.fetch(:reason)).to eq('rejected')
      }
    end

    it 'raises already_submitted once no uploaded documents remain' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      passport = create_requirement(assignment:, code: 'passport')
      create_required_documents(
        candidate:,
        assignment:,
        default_status: 'verified',
        overrides: {
          'passport' => { document_type: passport, status_code: 'under_verification' }
        }
      )

      expect do
        described_class.call(candidate:, request_id: 'candidate-submit-4')
      end.to raise_error(AlreadySubmittedError)
    end

    it 'rolls back document updates when audit creation fails' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      passport = create_requirement(assignment:, code: 'passport')
      create_required_documents(
        candidate:,
        assignment:,
        default_status: 'verified',
        overrides: {
          'passport' => { document_type: passport, status_code: 'uploaded' }
        }
      )
      document = CandidateDocument.current_version.find_by!(candidate_assignment: assignment, document_type: passport)

      allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))

      expect do
        described_class.call(candidate:, request_id: 'candidate-submit-5')
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(document.reload.status_code).to eq('uploaded')
      expect(CandidateDocumentSubmission.count).to eq(0)
    end

    it 'rolls back when document persistence fails mid-submission' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      passport = create_requirement(assignment:, code: 'passport')
      create_required_documents(
        candidate:,
        assignment:,
        default_status: 'verified',
        overrides: {
          'passport' => { document_type: passport, status_code: 'uploaded' }
        }
      )
      service = described_class.new(candidate:, request_id: 'candidate-submit-6')
      allow(service).to receive(:submit_document!).and_raise(ActiveRecord::RecordInvalid.new(CandidateDocument.new))

      expect do
        service.call
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(
        CandidateDocument.current_version.find_by!(
          candidate_assignment: assignment,
          document_type: passport
        ).status_code
      ).to eq('uploaded')
      expect(CandidateDocumentSubmission.count).to eq(0)
    end

    it 'allows only one concurrent successful submission' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      passport = create_requirement(assignment:, code: 'passport')
      create_required_documents(
        candidate:,
        assignment:,
        default_status: 'verified',
        overrides: {
          'passport' => { document_type: passport, status_code: 'uploaded' }
        }
      )
      outcomes = Queue.new

      worker = lambda do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.call(candidate:, request_id: SecureRandom.uuid)
          outcomes << :submitted
        rescue AlreadySubmittedError
          outcomes << :already_submitted
        end
      end

      threads = Array.new(2) { Thread.new(&worker) }
      threads.each(&:join)

      expect(Array.new(2) { outcomes.pop }).to contain_exactly(:submitted, :already_submitted)
      expect(CandidateDocumentSubmission.count).to eq(1)
      expect(
        CandidateDocument.current_version.find_by!(
          candidate_assignment: assignment,
          document_type: passport
        ).status_code
      )
        .to eq('under_verification')
    end
  end
end
