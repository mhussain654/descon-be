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

  it 'configures multi-file rules and bilingual instructions per document' do
    passport = DocumentRequirement.joins(:document_type).find_by!(document_types: { code: 'passport' }, country: nil)

    expect(passport).to have_attributes(minimum_files: 1, maximum_files: 2, combined_pdf_allowed: true,
                                        allowed_side_codes: %w[combined page_1 page_2], display_position: 1)
    expect(passport.instructions_for(locale: :en)).to include('first two pages')
    expect(passport.instructions_for(locale: :ur)).to include('پاسپورٹ')
  end

  it 'retires the superseded single-file types and stays idempotent' do
    legacy = create(:document_type, code: 'cnic_front')
    legacy_requirement = create(:document_requirement, document_type: legacy)

    expect { described_class.call }.not_to change(DocumentRequirement, :count)
    expect(legacy.reload.active).to be(false)
    expect(legacy_requirement.reload.active).to be(false)
  end
end
