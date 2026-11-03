# frozen_string_literal: true

namespace :mobilization_processes do
  desc 'Restarts every candidate still on a retired mobilization process at the first stage of their ' \
       'country\'s current process (one-off, for the switch to the finalized country flows while only ' \
       'test candidates exist). Their earlier stage progress is not kept. Run after db:seed.'
  task restart_on_current_process: :environment do
    restarted = MobilizationProcesses::RestartOnCurrentProcessService.call
    restarted.each do |assignment|
      puts "#{assignment.public_id}: now on #{assignment.mobilization_process.code} " \
           "v#{assignment.mobilization_process.version} at #{assignment.current_workflow_stage.code}"
    end
    puts "#{restarted.size} candidate assignment(s) restarted."
  end
end
