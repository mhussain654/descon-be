# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowStageCallScript do
  it 'has a valid factory' do
    expect(build(:workflow_stage_call_script)).to be_valid
  end

  it 'requires a workflow_stage_code that is one of the canonical stages' do
    script = build(:workflow_stage_call_script, workflow_stage_code: 'not_a_real_stage')

    expect(script).not_to be_valid
    expect(script.errors[:workflow_stage_code]).to be_present
  end

  it 'accepts any canonical workflow stage code' do
    WorkflowStage::CANONICAL_STAGES.each do |stage|
      script = build(:workflow_stage_call_script, workflow_stage_code: stage.fetch(:code))
      expect(script).to be_valid, "expected #{stage.fetch(:code)} to be a valid workflow_stage_code"
    end
  end

  it 'enforces one script per workflow stage' do
    create(:workflow_stage_call_script, workflow_stage_code: 'verified')
    duplicate = build(:workflow_stage_call_script, workflow_stage_code: 'verified')

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'requires a non-blank announcement_en' do
    script = build(:workflow_stage_call_script, announcement_en: '   ')

    expect(script).not_to be_valid
    expect(script.errors[:announcement_en]).to be_present
  end

  it 'allows a blank announcement_ur (Urdu wording may not be ready yet)' do
    script = build(:workflow_stage_call_script, announcement_ur: '   ')

    expect(script).to be_valid
    expect(script.announcement_ur).to be_nil
  end

  it 'normalizes the stage code and strips announcement whitespace' do
    script = create(:workflow_stage_call_script, workflow_stage_code: ' VERIFIED ', announcement_en: '  Hi  ')

    expect(script.workflow_stage_code).to eq('verified')
    expect(script.announcement_en).to eq('Hi')
  end

  describe '.active' do
    it 'scopes to scripts marked active' do
      active = create(:workflow_stage_call_script, workflow_stage_code: 'verified', active: true)
      create(:workflow_stage_call_script, workflow_stage_code: 'fee_paid', active: false)

      expect(described_class.active).to contain_exactly(active)
    end
  end
end
