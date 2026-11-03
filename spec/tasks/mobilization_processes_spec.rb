# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'mobilization_processes:restart_on_current_process rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before { Rake::Task['mobilization_processes:restart_on_current_process'].reenable }

  it 'restarts candidates left on a retired process and reports each one' do
    retired = MobilizationProcess.find_by!(code: 'common_mobilization', version: 1)
    assignment = create(:candidate_assignment, country: process_country(:oman), mobilization_process: retired,
                                               current_workflow_stage: WorkflowStage.find_by!(code: 'fee_pending'))

    expect { Rake::Task['mobilization_processes:restart_on_current_process'].invoke }
      .to output(/#{assignment.public_id}: now on oman_mobilization v1 at registered\n1 candidate assignment/)
      .to_stdout
  end
end
