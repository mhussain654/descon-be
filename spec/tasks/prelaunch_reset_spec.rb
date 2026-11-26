# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'prelaunch_reset rake tasks' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    ensure_staff_authorization_reference_data!
    Rake::Task['prelaunch_reset:preview'].reenable
    Rake::Task['prelaunch_reset:run'].reenable
  end

  it 'previews the counts and the confirm command without deleting anything' do
    create(:candidate)

    expect { Rake::Task['prelaunch_reset:preview'].invoke }
      .to output(%r{candidates.*To run it: bin/rails prelaunch_reset:run CONFIRM=DELETE-ALL-TEST-DATA}m).to_stdout
    expect(Candidate.count).to be_positive
  end

  it 'refuses to run without the confirmation word' do
    create(:candidate)

    expect do
      Rake::Task['prelaunch_reset:run'].invoke
    end.to raise_error(SystemExit).and output(/DELETE-ALL-TEST-DATA/).to_stderr
    expect(Candidate.count).to be_positive
  end

  it 'runs with the confirmation word and reminds to seed' do
    create(:user, role: 'developer')
    create(:candidate)

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CONFIRM', nil).and_return('DELETE-ALL-TEST-DATA')

    expect { Rake::Task['prelaunch_reset:run'].invoke }.to output(%r{Now run: bin/rails db:seed}).to_stdout
    expect(Candidate.count).to eq(0)
  end
end
