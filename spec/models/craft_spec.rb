# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Craft, type: :model do
  subject(:craft) { build(:craft) }

  it { is_expected.to validate_uniqueness_of(:code) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:craft, name_en: 'Welder', name_ur: 'ویلڈر') }
    let(:expected_english_name) { 'Welder' }
    let(:expected_urdu_name) { 'ویلڈر' }
  end
end
