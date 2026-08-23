# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Project, type: :model do
  subject(:project) { build(:project) }

  it { is_expected.to validate_uniqueness_of(:code) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:project, name_en: 'North Field', name_ur: 'نارتھ فیلڈ') }
    let(:expected_english_name) { 'North Field' }
    let(:expected_urdu_name) { 'نارتھ فیلڈ' }
  end
end
