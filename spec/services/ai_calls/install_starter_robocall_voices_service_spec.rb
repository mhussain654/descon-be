# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::InstallStarterRobocallVoicesService do
  let(:starter) { described_class::STARTER_VOICES }

  it 'adds every starter voice as a call type and sets it, switched off, on its stage' do
    described_class.call

    expect(RobocallVoice.where(voice_id: starter.pluck(:voice_id)).count).to eq(starter.size)
    starter.each do |entry|
      script = WorkflowStageCallScript.find_by!(workflow_stage_code: entry.fetch(:stage_code))
      expect(script).to have_attributes(voice_id: entry.fetch(:voice_id), active: false)
    end
  end

  it 'leaves anything an admin already changed alone, and can run twice' do
    edited = create(:robocall_voice, voice_id: '538', name_en: 'My upload call')
    WorkflowStageCallScript.create!(workflow_stage_code: 'documents_pending', voice_id: '999', active: true)

    2.times { described_class.call }

    expect(RobocallVoice.count).to eq(starter.size)
    expect(edited.reload.name_en).to eq('My upload call')
    expect(WorkflowStageCallScript.find_by!(workflow_stage_code: 'documents_pending'))
      .to have_attributes(voice_id: '999', active: true)
  end

  it 'only uses stages that exist and voice ids the call types accept' do
    codes = WorkflowStage::CANONICAL_STAGES.pluck(:code)

    expect(starter.pluck(:stage_code) - codes).to be_empty
    expect(starter.pluck(:voice_id)).to all(match(RobocallVoice::VOICE_ID_FORMAT))
    expect(starter.pluck(:voice_id)).to eq(starter.pluck(:voice_id).uniq)
  end
end
