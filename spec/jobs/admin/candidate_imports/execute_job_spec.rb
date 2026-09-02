# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateImports::ExecuteJob, type: :job do
  include ActiveJob::TestHelper

  it 'delegates execution with safe identifiers only' do
    allow(Admin::Candidates::Imports::BatchExecutionService).to receive(:call)

    perform_enqueued_jobs { described_class.perform_later('d2e5f5b2-6f10-4eef-8f3a-1c1d8a4ec01f', 'request-1') }

    expect(Admin::Candidates::Imports::BatchExecutionService).to have_received(:call).with(
      import_id: 'd2e5f5b2-6f10-4eef-8f3a-1c1d8a4ec01f', request_id: 'request-1'
    )
  end

  it 'records a failed batch when execution raises' do
    allow(Admin::Candidates::Imports::BatchExecutionService).to receive(:call).and_raise(ActiveRecord::RecordInvalid)
    allow(Admin::Candidates::Imports::BatchExecutionService).to receive(:record_failure)

    expect do
      described_class.perform_now('d2e5f5b2-6f10-4eef-8f3a-1c1d8a4ec01f', 'request-2')
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(Admin::Candidates::Imports::BatchExecutionService).to have_received(:record_failure).with(
      import_id: 'd2e5f5b2-6f10-4eef-8f3a-1c1d8a4ec01f', request_id: 'request-2'
    )
  end
end
