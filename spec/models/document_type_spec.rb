# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentType, type: :model do
  subject(:document_type) { build(:document_type) }

  it { is_expected.to validate_uniqueness_of(:code) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:document_type, name_en: 'Passport', name_ur: 'پاسپورٹ') }
    let(:expected_english_name) { 'Passport' }
    let(:expected_urdu_name) { 'پاسپورٹ' }
  end

  describe '#supports_ocr_extraction?' do
    it 'is true for passport, cnic_front, cnic_back and next_of_kin_cnic' do
      %w[passport cnic_front cnic_back next_of_kin_cnic].each do |code|
        expect(build(:document_type, code:)).to be_supports_ocr_extraction
      end
    end

    it 'is false for every other document type, including police_character which also requires_expiry' do
      expect(build(:document_type, code: 'police_character', requires_expiry: true)).not_to be_supports_ocr_extraction
      expect(build(:document_type, code: 'cv')).not_to be_supports_ocr_extraction
    end
  end
end
