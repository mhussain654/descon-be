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
end
