# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'deployment rake tasks' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def passing(name) = Deployment::CheckResult.new(name:, status: :pass, detail: 'fine')
  def failing(name) = Deployment::CheckResult.new(name:, status: :fail, detail: 'broken')

  describe 'deployment:preflight' do
    before { Rake::Task['deployment:preflight'].reenable }

    it 'prints every check and a final pass line when nothing failed' do
      allow(Deployment::PreflightCheck).to receive(:call).and_return([passing('primary database')])

      expect { Rake::Task['deployment:preflight'].invoke }
        .to output(/\[PASS\] primary database: fine\nDeployment check passed\./).to_stdout
    end

    it 'prints every check and exits non-zero when any check failed' do
      allow(Deployment::PreflightCheck).to receive(:call).and_return([passing('a'), failing('pg_dump')])

      expect do
        expect { Rake::Task['deployment:preflight'].invoke }.to output(/\[FAIL\] pg_dump: broken/).to_stdout
      end.to raise_error(SystemExit)
    end
  end

  describe 'deployment:queue_status' do
    before { Rake::Task['deployment:queue_status'].reenable }

    it 'reports the Solid Queue check' do
      allow(Deployment::QueueStatusCheck).to receive(:call).and_return(passing('solid queue'))

      expect { Rake::Task['deployment:queue_status'].invoke }.to output(/\[PASS\] solid queue/).to_stdout
    end
  end

  describe 'deployment:storage_round_trip' do
    before { Rake::Task['deployment:storage_round_trip'].reenable }

    it 'reports each storage step' do
      allow(Deployment::StorageRoundTripCheck).to receive(:call).and_return([passing('upload/read-back')])

      expect { Rake::Task['deployment:storage_round_trip'].invoke }.to output(%r{\[PASS\] upload/read-back}).to_stdout
    end
  end
end
