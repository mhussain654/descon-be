# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260904090000_retire_generic_bank_document_requirements')

RSpec.describe RetireGenericBankDocumentRequirements do
  subject(:migration) { described_class.new }

  def requirement_for(code)
    document_type = DocumentType.find_by(code:) || create(:document_type, code:)
    DocumentRequirement.find_by(document_type:) ||
      create(:document_requirement, document_type:, country: nil, project: nil, craft: nil, active: true)
  end

  describe '#up' do
    it 'deactivates the bank_details and cheque_image document requirements' do
      bank_details = requirement_for('bank_details')
      cheque_image = requirement_for('cheque_image')

      migration.up

      expect(bank_details.reload.active).to be(false)
      expect(cheque_image.reload.active).to be(false)
    end

    it 'leaves every other document requirement untouched' do
      passport = requirement_for('passport')

      migration.up

      expect(passport.reload.active).to be(true)
    end

    it 'removes bank_details/cheque_image from RequirementResolver output for a real assignment' do
      requirement_for('bank_details')
      requirement_for('cheque_image')
      assignment = create(:candidate_assignment)

      migration.up

      codes = Candidates::Documents::RequirementResolver.call(candidate: assignment.candidate).map { |r| r.document_type.code }
      expect(codes).not_to include('bank_details', 'cheque_image')
    end
  end

  describe '#down' do
    it 'reactivates the bank_details and cheque_image document requirements' do
      bank_details = requirement_for('bank_details')
      cheque_image = requirement_for('cheque_image')
      migration.up

      migration.down

      expect(bank_details.reload.active).to be(true)
      expect(cheque_image.reload.active).to be(true)
    end
  end
end
