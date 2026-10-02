# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'mobilization:backfill_processes rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task['mobilization:backfill_processes'].reenable
  end

  it 'reports how many assignments were linked and which were left unlinked' do
    result = MobilizationProcesses::AssignmentBackfill::Result.new(linked_count: 3,
                                                                   unmatched_reference_numbers: %w[DES-1 DES-2])
    allow(MobilizationProcesses::AssignmentBackfill).to receive(:call).and_return(result)

    expect { Rake::Task['mobilization:backfill_processes'].invoke }
      .to output(/Linked 3 assignment\(s\).*left unlinked\): DES-1, DES-2/m).to_stdout
  end

  it 'prints only the linked count when every assignment matched' do
    result = MobilizationProcesses::AssignmentBackfill::Result.new(linked_count: 0, unmatched_reference_numbers: [])
    allow(MobilizationProcesses::AssignmentBackfill).to receive(:call).and_return(result)

    expect { Rake::Task['mobilization:backfill_processes'].invoke }
      .to output("Linked 0 assignment(s) to a mobilization process.\n").to_stdout
  end
end
