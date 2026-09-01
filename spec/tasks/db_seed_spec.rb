# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'db:seed rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task['db:seed'].reenable
  end

  it 'runs cleanly against the current (fresh, migrated, empty) database' do
    expect { Rake::Task['db:seed'].invoke }.not_to raise_error
  end

  it 'is idempotent -- running it again does not raise or create duplicates' do
    Rake::Task['db:seed'].invoke
    Rake::Task['db:seed'].reenable
    counts_before = %w[Country Project Craft DocumentType Role Permission WorkflowStage Candidate]
                    .map { |name| name.constantize.count }

    expect { Rake::Task['db:seed'].invoke }.not_to raise_error

    counts_after = %w[Country Project Craft DocumentType Role Permission WorkflowStage Candidate]
                   .map { |name| name.constantize.count }
    expect(counts_after).to eq(counts_before)
  end

  it 'seeds the roles, permissions and canonical workflow stages required by MPS-106' do
    Rake::Task['db:seed'].invoke

    expect(Role.pluck(:code)).to match_array(Role::SYSTEM_ROLES.map { |r| r.fetch(:code) })
    expect(WorkflowStage.count).to eq(15)
    expect(WorkflowStage.pluck(:code)).to match_array(WorkflowStage::CANONICAL_STAGES.map { |s| s.fetch(:code) })
  end

  it 'seeds reference catalogs: countries, projects, crafts and document types' do
    Rake::Task['db:seed'].invoke

    expect(Country.count).to be_positive
    expect(Project.count).to be_positive
    expect(Craft.count).to be_positive
    expect(DocumentType.pluck(:code)).to include('passport', 'cnic_front', 'cnic_back', 'cv')
  end

  it 'does not seed the demo candidates (or their supporting user) in the test environment' do
    # db:prepare runs this file for real -- not inside a rolled-back RSpec
    # transaction -- against a freshly created database (e.g. in CI). The
    # demo candidates exist for manual/frontend exploratory testing against
    # a real running server, not as automated-test fixtures; seeding them
    # here would leave a real, persisted User + Candidate rows that
    # pre-existing specs (e.g. Idempotency::RequestHandler's `User.
    # delete_all` cleanup, the users index pagination spec) never accounted
    # for. This regression-tests the fix, not just the feature.
    Rake::Task['db:seed'].invoke

    expect(Candidate.count).to eq(0)
    expect(User.find_by(email: 'seed-data@descon.local')).to be_nil
  end

  it 'does not seed the reserved demo candidates by default outside development' do
    allow(Rails.env).to receive_messages(test?: false, development?: false)

    Rake::Task['db:seed'].invoke

    expect(Candidate.find_by(cnic: '11111-1111111-1')).to be_nil
    expect(Candidate.find_by(cnic: '22222-2222222-2')).to be_nil
    expect(User.find_by(email: 'seed-data@descon.local')).to be_nil
  end

  it 'seeds the reserved demo candidates only in development with explicit opt-in' do
    allow(Rails.env).to receive(:development?).and_return(true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('SEED_DEMO_DATA', 'false').and_return('true')

    Rake::Task['db:seed'].invoke

    valid = Candidate.find_by(cnic: '11111-1111111-1')
    undeliverable = Candidate.find_by(cnic: '22222-2222222-2')

    expect(valid).to be_present
    expect(valid.mobile_number).to eq('+923001234567')
    expect(undeliverable).to be_present
    expect(undeliverable.mobile_number).to eq('+920000000000')
    expect(Candidate.find_by(cnic: '99999-9999999-9')).to be_nil
  end
end
