# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Role, type: :model do
  subject(:role) { build(:role) }

  it { is_expected.to have_many(:users).with_foreign_key(:role).with_primary_key(:code) }
  it { is_expected.to have_many(:role_permissions).dependent(:destroy) }
  it { is_expected.to have_many(:permissions).through(:role_permissions) }
  it { is_expected.to validate_uniqueness_of(:code) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:role, code: 'admin') }
    let(:expected_english_name) { 'Administrator' }
    let(:expected_urdu_name) { 'منتظم' }
  end
end
