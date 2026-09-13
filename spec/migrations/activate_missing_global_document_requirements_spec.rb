# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260912100000_activate_missing_global_document_requirements')

RSpec.describe ActivateMissingGlobalDocumentRequirements do
  subject(:migration) { described_class.new }

  # Other specs elsewhere in the suite create their own DocumentRequirement
  # rows for these same well-known codes (including scoped to a factory
  # country/project/craft), and this suite has pre-existing cross-example
  # isolation gaps that occasionally leave such rows behind. This example
  # group's assertions are about exactly which requirement rows exist for
  # these three document types, so it needs a genuinely clean slate for them
  # regardless of what ran earlier -- stripping every existing row (any
  # scope) up front makes every example here deterministic independent of
  # suite order, per AGENTS.md's "keep examples deterministic and independent
  # of execution order."
  before do
    DocumentRequirement.where(
      document_type_id: DocumentType.where(code: described_class::ACTIVATED_CODES).select(:id)
    ).delete_all
  end

  def document_type_for(code)
    DocumentType.find_by(code:) || create(:document_type, code:)
  end

  describe '#up' do
    it 'creates a required, active global requirement for a code with no requirement row at all' do
      document_type_for('passport')
      expect(DocumentRequirement.find_by(document_type: document_type_for('passport'))).to be_nil

      migration.up

      requirement = DocumentRequirement.find_by!(document_type: document_type_for('passport'))
      expect(requirement.required).to be(true)
      expect(requirement.active).to be(true)
      expect(requirement.country_id).to be_nil
      expect(requirement.project_id).to be_nil
      expect(requirement.craft_id).to be_nil
    end

    it 'activates cnic_front and police_character the same way' do
      cnic_front = document_type_for('cnic_front')
      police_character = document_type_for('police_character')

      migration.up

      expect(DocumentRequirement.find_by!(document_type: cnic_front).active).to be(true)
      expect(DocumentRequirement.find_by!(document_type: police_character).active).to be(true)
    end

    it 'is idempotent -- running it twice does not create duplicate requirement rows' do
      document_type = document_type_for('passport')

      migration.up
      migration.up

      expect(DocumentRequirement.where(document_type:).count).to eq(1)
    end

    it 'makes passport, cnic_front and police_character appear in RequirementResolver output for a real assignment' do
      document_type_for('passport')
      document_type_for('cnic_front')
      document_type_for('police_character')
      assignment = create(:candidate_assignment)

      migration.up

      codes = Candidates::Documents::RequirementResolver.call(candidate: assignment.candidate)
                                                        .map { |r| r.document_type.code }
      expect(codes).to include('passport', 'cnic_front', 'police_character')
    end

    it 'leaves an existing requirement for one of the codes untouched if already active' do
      document_type = document_type_for('passport')
      create(:document_requirement, document_type:, country: nil, project: nil, craft: nil, required: true,
                                    active: true)

      expect { migration.up }.not_to raise_error
      expect(DocumentRequirement.where(document_type:).count).to eq(1)
    end
  end

  describe '#down' do
    it 'deactivates the global requirement for each activated code' do
      passport = document_type_for('passport')
      cnic_front = document_type_for('cnic_front')
      police_character = document_type_for('police_character')
      migration.up

      migration.down

      expect(DocumentRequirement.find_by!(document_type: passport).active).to be(false)
      expect(DocumentRequirement.find_by!(document_type: cnic_front).active).to be(false)
      expect(DocumentRequirement.find_by!(document_type: police_character).active).to be(false)
    end
  end
end
