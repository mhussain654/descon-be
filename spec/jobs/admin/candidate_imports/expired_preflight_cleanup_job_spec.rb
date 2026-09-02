# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateImports::ExpiredPreflightCleanupJob, type: :job do
  include ActiveJob::TestHelper

  it 'delegates expired payload cleanup' do
    allow(Admin::Candidates::Imports::ExpiredPreflightCleanupService).to receive(:call)

    perform_enqueued_jobs { described_class.perform_later }

    expect(Admin::Candidates::Imports::ExpiredPreflightCleanupService).to have_received(:call)
  end
end
