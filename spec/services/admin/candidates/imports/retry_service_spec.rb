# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::Imports::RetryService do
  let(:actor) { create(:user) }

  it 'requeues an unexpired failed batch even when it was previously enqueued' do
    batch = create(:candidate_import_batch, actor:, status: 'failed', enqueued_at: 1.hour.ago, failed_at: 1.hour.ago)

    result = described_class.call(actor:, batch:, request_id: 'retry-import-1')

    expect(result).to have_attributes(status: 'queued', error_code: nil)
    expect(result.enqueued_at).to be > 1.minute.ago
    expect(AuditEvent.where(action_code: 'candidate_import_retried', entity_id: batch.id).count).to eq(1)
    expect(AuditEvent.last.metadata).to eq('import_public_id' => batch.public_id)
  end

  it 'rejects completed and expired batches' do
    completed = create(:candidate_import_batch, actor:, status: 'completed')
    expired = create(:candidate_import_batch, actor:, status: 'failed', expires_at: 1.minute.ago)

    [completed, expired].each do |batch|
      expect do
        described_class.call(actor:, batch:, request_id: SecureRandom.uuid)
      end.to raise_error(ValidationError) { |error| expect(error.field).to eq('candidate_import.status') }
    end
  end

  it 'allows only one concurrent retry to requeue a failed batch' do
    batch = create(:candidate_import_batch, actor:, status: 'failed')
    outcomes = Queue.new

    worker = lambda do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.call(actor:, batch:, request_id: SecureRandom.uuid)
        outcomes << :requeued
      rescue ValidationError
        outcomes << :rejected
      end
    end

    threads = Array.new(2) { Thread.new(&worker) }
    threads.each(&:join)

    expect(Array.new(2) { outcomes.pop }).to contain_exactly(:requeued, :rejected)
    expect(AuditEvent.where(action_code: 'candidate_import_retried', entity_id: batch.id).count).to eq(1)
  end
end
