# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it { is_expected.to have_many(:sessions).dependent(:destroy) }
  it { is_expected.to validate_uniqueness_of(:public_id) }

  it 'assigns a public_id on create' do
    user.public_id = nil

    user.validate

    expect(user.public_id).to be_present
  end
end
