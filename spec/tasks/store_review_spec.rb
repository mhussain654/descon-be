# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'store_review:create_candidate rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task['store_review:create_candidate'].reenable
    create(:project, code: 'qatar_infrastructure') unless Project.exists?(code: 'qatar_infrastructure')
    create(:craft, code: 'electrician') unless Craft.exists?(code: 'electrician')
    allow(StoreReview::Account).to receive(:setting).with(:cnic).and_return('12345-6789012-3')
    allow(StoreReview::Account).to receive(:setting).with(:otp_code).and_return('246810')
  end

  it 'creates the reviewer candidate at Enrolled' do
    admin = create(:user, role: 'admin')

    expect { Rake::Task['store_review:create_candidate'].invoke(admin.email) }
      .to output(/Store reviewer candidate .+ is at registered\./).to_stdout
  end

  it 'stops when the creator email matches no staff user' do
    expect { Rake::Task['store_review:create_candidate'].invoke('nobody@example.com') }
      .to raise_error(SystemExit).and output(/Pass an existing staff user email/).to_stderr
  end

  it 'stops when the credentials are not set' do
    allow(StoreReview::Account).to receive(:setting).and_return('')
    admin = create(:user, role: 'admin')

    expect { Rake::Task['store_review:create_candidate'].invoke(admin.email) }
      .to raise_error(SystemExit).and output(/Set store_review cnic and otp_code/).to_stderr
  end
end
