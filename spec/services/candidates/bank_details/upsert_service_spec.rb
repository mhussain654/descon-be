# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::BankDetails::UpsertService do
  def proof_upload(name = 'test.pdf', content_type = 'application/pdf')
    fixture_upload(name, content_type)
  end

  describe '.call' do
    it 'creates a current bank detail and records a safe audit event' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)

      result = described_class.call(
        candidate:,
        account_title: ' Ahmed Ali ',
        account_number: 'pk24 scbl 0000001123456702',
        bank_name: ' Sample Bank ',
        proof: proof_upload,
        request_id: 'request-1'
      )

      expect(result).to be_created
      expect(result.bank_detail.candidate_assignment).to eq(assignment)
      expect(result.bank_detail.account_number).to eq('PK24SCBL0000001123456702')
      expect(result.bank_detail.proof).to be_attached

      event = AuditEvent.order(:id).last
      expect(event.action_code).to eq('candidate_bank_detail_submitted')
      expect(event.metadata).to include(
        'candidate_public_id' => candidate.public_id,
        'candidate_assignment_public_id' => assignment.public_id,
        'bank_detail_public_id' => result.bank_detail.public_id
      )
      expect(event.metadata.keys).not_to include('account_number', 'account_title', 'bank_name', 'proof_filename')
    end

    it 'preserves the previous current record and proof when replacement fails' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      current_record = create(:candidate_bank_detail, candidate_assignment: assignment, account_number: 'PK24SCBL0001')
      failing_event = build(:audit_event)

      allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(failing_event))

      expect do
        described_class.call(
          candidate:,
          account_title: 'Updated Name',
          account_number: 'PK24SCBL0002',
          bank_name: 'Updated Bank',
          proof: proof_upload,
          request_id: 'request-2'
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(current_record.reload).to be_current_version
      expect(current_record.account_title).to eq('Ahmed Ali')
      expect(current_record.proof).to be_attached
      expect(assignment.candidate_bank_details.current_version.count).to eq(1)
      expect(assignment.candidate_bank_details.count).to eq(1)
    end
  end
end
