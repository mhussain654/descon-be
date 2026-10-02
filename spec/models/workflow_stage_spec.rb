# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowStage, type: :model do
  subject(:workflow_stage) { build(:workflow_stage) }

  it { is_expected.to validate_uniqueness_of(:code) }
  it { is_expected.to validate_uniqueness_of(:position) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:workflow_stage, code: 'verified') }
    let(:expected_english_name) { 'Documents Verified' }
    let(:expected_urdu_name) { 'دستاویزات کی تصدیق ہو گئی' }
  end

  it 'defines the 30-stage catalog that every mobilization process draws from' do
    expect(described_class::CANONICAL_STAGES.size).to eq(30)
    expect(described_class::CANONICAL_STAGES.pluck(:position)).to eq((1..30).to_a)
    expect(described_class::CANONICAL_STAGES.pluck(:code)).not_to include('protected_ready_to_fly')
  end

  it 'prevents mutating system-defined stage identifiers' do
    stage = create(:workflow_stage, :registered)

    stage.code = 'changed'

    expect(stage).not_to be_valid
    expect(stage.errors[:base]).to be_present
  end

  it 'prevents changing system-defined stages to non-system-defined' do
    stage = create(:workflow_stage, :registered)

    stage.system_defined = false

    expect(stage).not_to be_valid
    expect(stage.errors[:base]).to be_present
  end

  it 'prevents changing system-defined stage positions' do
    stage = create(:workflow_stage, :registered)

    stage.position = 99

    expect(stage).not_to be_valid
    expect(stage.errors[:base]).to be_present
  end

  it 'prevents destroying system-defined stages' do
    stage = create(:workflow_stage, :registered)

    expect(stage.destroy).to be(false)
  end
end
