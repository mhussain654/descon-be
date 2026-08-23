# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Country, type: :model do
  subject(:country) { build(:country) }

  it { is_expected.to validate_uniqueness_of(:code) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:country, name_en: 'Qatar', name_ur: 'قطر') }
    let(:expected_english_name) { 'Qatar' }
    let(:expected_urdu_name) { 'قطر' }
  end
end
