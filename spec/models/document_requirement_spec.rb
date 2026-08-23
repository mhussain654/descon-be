# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentRequirement, type: :model do
  subject(:document_requirement) { build(:document_requirement) }

  it { is_expected.to belong_to(:document_type) }
  it { is_expected.to belong_to(:country).optional }
  it { is_expected.to belong_to(:project).optional }
  it { is_expected.to belong_to(:craft).optional }

  it 'prevents duplicate document scopes' do
    document_type = create(:document_type)
    country = create(:country)
    create(:document_requirement, document_type:, country:)

    duplicate_requirement = build(:document_requirement, document_type:, country:)

    expect(duplicate_requirement).not_to be_valid
    expect(duplicate_requirement.errors[:document_type_id]).to include('has already been taken')
  end
end
