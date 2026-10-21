# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowStageCallScript do
  # db:seed creates a default script row for several canonical stages
  # (including 'verified' and 'fee_paid', used by name throughout this file)
  # for real against a freshly prepared test database (see
  # spec/tasks/db_seed_spec.rb's comment on db:prepare running seeds outside
  # any rolled-back RSpec transaction). These examples assert about exactly
  # which rows exist per stage code, so they need a clean slate regardless of
  # what seeded earlier (AGENTS.md: "keep examples deterministic and
  # independent of execution order").
  before { described_class.delete_all }

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

  describe 'voice_id' do
    it 'accepts a RoboCall voice id and then needs no announcement text' do
      script = build(:workflow_stage_call_script, voice_id: ' 102 ', announcement_en: nil, announcement_ur: nil)

      expect(script).to be_valid
      expect(script.voice_id).to eq('102')
    end

    it 'still requires an announcement when there is no voice id' do
      expect(build(:workflow_stage_call_script, voice_id: '', announcement_en: nil)).not_to be_valid
    end

    it 'rejects a voice id with unsafe characters or excessive length' do
      ['10 2', '102;drop', 'a' * 33, 'ہوا'].each do |bad|
        expect(build(:workflow_stage_call_script, voice_id: bad)).not_to be_valid, "expected #{bad.inspect} invalid"
      end
    end
  end

  describe '.active' do
    it 'scopes to scripts marked active' do
      active = create(:workflow_stage_call_script, workflow_stage_code: 'verified', active: true)
      create(:workflow_stage_call_script, workflow_stage_code: 'fee_paid', active: false)

      expect(described_class.active).to contain_exactly(active)
    end
  end
end
