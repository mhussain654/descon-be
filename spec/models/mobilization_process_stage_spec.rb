# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MobilizationProcessStage, type: :model do
  let(:process) { MobilizationProcess.create!(code: 'stage_spec_process', version: 1, country: create(:country)) }

  def build_stage(**attributes)
    process.stages.build(workflow_stage: WorkflowStage.find_by!(code: 'registered'), position: 1,
                         action_type: 'none', **attributes)
  end

  it 'accepts only known action types, positive positions and object configuration' do
    expect(build_stage).to be_valid
    expect(build_stage(action_type: 'teleport')).not_to be_valid
    expect(build_stage(position: 0)).not_to be_valid
    expect(build_stage(configuration: [])).not_to be_valid
  end

  it 'keeps positions and catalog stages unique within a process' do
    build_stage.save!

    expect(build_stage(workflow_stage: WorkflowStage.find_by!(code: 'verified'))).not_to be_valid
    expect(build_stage(position: 2)).not_to be_valid
  end

  it "identifies each process's last stage as terminal" do
    terminal_codes = described_class.terminal.includes(:workflow_stage, :mobilization_process)
                                    .to_h { |stage| [stage.mobilization_process.code, stage.code] }

    expect(terminal_codes).to include('qatar_mobilization' => 'mobilized', 'ksa_mobilization' => 'ticket_handover',
                                      'common_mobilization' => 'ticket_handover')
  end
end
