# frozen_string_literal: true

require 'rails_helper'

# The approved checklists, end to end: the seeded catalog resolved for each
# kind of assignment.
RSpec.describe DocumentChecklists::Seeder do
  let(:common_codes) do
    %w[passport cnic photograph next_of_kin_cnic cv educational_certificates experience_certificates cheque_copy]
  end

  before { described_class.call }

  def checklist_codes(country:, craft: create(:craft))
    assignment = create(:candidate_assignment, country:, craft:)
    Candidates::Documents::RequirementResolver.call(candidate: assignment.candidate, assignment:)
                                              .map { |requirement| requirement.document_type.code }
  end

  it 'gives KSA candidates the common checklist plus the GAMCA/Wafid medical report, and no Qatar documents' do
    codes = checklist_codes(country: process_country(:saudi_arabia))

    expect(codes).to eq(common_codes + %w[gamca_medical_report])
  end

  it 'gives Qatar non-drivers the common checklist plus PCC and polio, without the driving licence' do
    codes = checklist_codes(country: process_country(:qatar), craft: create(:craft, is_driver: false))

    expect(codes).to eq(common_codes + %w[police_character polio_certificate])
  end

  it 'adds the Qatar driving licence only for a driver craft' do
    codes = checklist_codes(country: process_country(:qatar), craft: create(:craft, is_driver: true))

    expect(codes.last).to eq('qatar_driving_licence')
  end

  it 'never gives the driving licence to a KSA driver' do
    codes = checklist_codes(country: process_country(:saudi_arabia), craft: create(:craft, is_driver: true))

    expect(codes).not_to include('qatar_driving_licence')
  end

  it 'gives a provisional-country candidate the common checklist only' do
    expect(checklist_codes(country: create(:country))).to eq(common_codes)
  end

  it 'asks for every document as a scanned PDF, with bilingual instructions' do
    passport = DocumentRequirement.joins(:document_type).find_by!(document_types: { code: 'passport' }, country: nil)

    expect(passport).to have_attributes(minimum_files: 1, maximum_files: 1, combined_pdf_allowed: true,
                                        allowed_side_codes: %w[combined], display_position: 1)
    expect(passport.instructions_for(locale: :en)).to include('latest passport')
    expect(passport.instructions_for(locale: :ur)).to include('پاسپورٹ')
    catalog_codes = DocumentChecklists::Definitions::DOCUMENT_TYPES.pluck(:code)
    catalog_rows = DocumentRequirement.joins(:document_type).where(active: true, project_id: nil, craft_id: nil,
                                                                   document_types: { code: catalog_codes })
    expect(catalog_rows.pluck(:accepted_content_types).uniq).to eq([%w[application/pdf]])
  end

  it 'names the next of kin document without "Legal Heir" and explains who can be next of kin' do
    next_of_kin = DocumentRequirement.joins(:document_type).find_by!(document_types: { code: 'next_of_kin_cnic' })

    expect(next_of_kin.document_type.name_en).to eq('Next of Kin CNIC')
    expect(next_of_kin.instructions_for(locale: :en)).to include('unmarried sister or daughter')
  end

  it 'adds the marriage certificate after the next of kin CNIC only when the next of kin is the wife' do
    assignment = create(:candidate_assignment, country: process_country(:saudi_arabia))
    codes = -> { Candidates::Documents::RequirementResolver.call(candidate: assignment.candidate, assignment:).map { |r| r.document_type.code } }
    next_of_kin_type = DocumentType.find_by!(code: 'next_of_kin_cnic')

    expect(codes.call).not_to include('marriage_certificate')
    document = create(:candidate_document, candidate_assignment: assignment, document_type: next_of_kin_type,
                                           next_of_kin_relation: 'brother')
    expect(codes.call).not_to include('marriage_certificate')

    document.update!(next_of_kin_relation: 'wife')
    expect(codes.call.each_cons(2)).to include(%w[next_of_kin_cnic marriage_certificate])
  end

  it 'retires the superseded single-file types and stays idempotent' do
    legacy = create(:document_type, code: 'cnic_front')
    legacy_requirement = create(:document_requirement, document_type: legacy)

    expect { described_class.call }.not_to change(DocumentRequirement, :count)
    expect(legacy.reload.active).to be(false)
    expect(legacy_requirement.reload.active).to be(false)
  end
end
