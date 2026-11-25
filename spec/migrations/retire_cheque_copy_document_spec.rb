# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261125110000_retire_cheque_copy_document')

RSpec.describe RetireChequeCopyDocument do
  subject(:migration) { described_class.new }

  let(:cheque_copy) { create(:document_type, code: 'cheque_copy', active: true) }
  let!(:catalog_row) { create(:document_requirement, document_type: cheque_copy) }
  let!(:project_row) { create(:document_requirement, document_type: cheque_copy, project: create(:project)) }

  def checklist_codes(assignment)
    Candidates::Documents::RequirementResolver.call(candidate: assignment.candidate, assignment:)
                                              .map { |requirement| requirement.document_type.code }
  end

  describe '#up' do
    it 'deactivates the cheque copy type and every requirement row for it' do
      migration.up

      expect(cheque_copy.reload.active).to be(false)
      expect([catalog_row.reload.active, project_row.reload.active]).to eq([false, false])
    end

    it 'leaves other document requirements untouched' do
      passport = create(:document_requirement, document_type: create(:document_type, code: 'passport'))

      migration.up

      expect(passport.reload.active).to be(true)
    end

    it 'removes the cheque copy from a candidate checklist' do
      assignment = create(:candidate_assignment)
      expect(checklist_codes(assignment)).to include('cheque_copy')

      migration.up

      expect(checklist_codes(assignment)).not_to include('cheque_copy')
    end
  end

  describe '#down' do
    it 'reactivates the type and the catalog row only' do
      migration.up

      migration.down

      expect(cheque_copy.reload.active).to be(true)
      expect([catalog_row.reload.active, project_row.reload.active]).to eq([true, false])
    end
  end
end
