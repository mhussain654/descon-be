# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowStage, type: :model do
  subject(:workflow_stage) { build(:workflow_stage) }

  it { is_expected.to validate_uniqueness_of(:code) }
  it { is_expected.to validate_uniqueness_of(:position) }

  it_behaves_like 'a localized reference model' do
    let(:record) { build(:workflow_stage, code: 'verified') }
    let(:expected_english_name) { 'Verified' }
    let(:expected_urdu_name) { 'تصدیق شدہ' }
  end

  it 'defines the canonical 15-stage workflow with under_verification in position 4' do
    expect(described_class::CANONICAL_STAGES.size).to eq(15)
    expect(described_class::CANONICAL_STAGES[3]).to include(code: 'under_verification', position: 4)
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
