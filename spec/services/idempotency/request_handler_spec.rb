# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Idempotency::RequestHandler do
  self.use_transactional_tests = false

  around do |example|
    RefreshToken.delete_all
    Session.delete_all
    User.delete_all
    IdempotencyKey.delete_all
    example.run
  ensure
    IdempotencyKey.delete_all
    RefreshToken.delete_all
    Session.delete_all
    User.delete_all
  end

  def execute_request(**overrides, &block)
    described_class.call(
      key: 'request-key-123',
      scope: 'foundation.mutation',
      request_context: default_request_metadata.merge(operation: block),
      **overrides
    )
  end

  def success_payload(data = {})
    {
      type: :success,
      data:,
      status: :ok,
      meta: { timestamp: Time.current.utc.iso8601 }
    }
  end

  def default_request_metadata
    {
      method: 'POST',
      path: '/foundation/mutation',
      fingerprint: 'fingerprint-a'
    }
  end

  it 'prevents double execution for concurrent requests with the same key' do
    started = Queue.new
    releases = Queue.new
    results = Queue.new
    executions = Concurrent::AtomicFixnum.new(0)

    worker = lambda do
      ActiveRecord::Base.connection_pool.with_connection do
        execute_request do
          executions.increment
          started << true
          releases.pop
          success_payload(ok: true)
        end
      rescue IdempotencyInProgressError => e
        results << e.code
      else
        results << :completed
      end
    end

    first_thread = Thread.new(&worker)
    started.pop
    second_thread = Thread.new(&worker)
    sleep 0.05
    releases << true
    [first_thread, second_thread].each(&:join)

    expect(Array.new(2) { results.pop }).to contain_exactly(:completed, 'idempotency_in_progress')
    expect(executions.value).to eq(1)
    expect(IdempotencyKey.count).to eq(1)
  end

  it 'allows the same key to be reused by different users because the scope is subject-aware' do
    user_a = create(:user, email: "user-a-#{SecureRandom.hex(4)}@example.com")
    user_b = create(:user, email: "user-b-#{SecureRandom.hex(4)}@example.com")

    first = execute_request(subject: user_a) { success_payload(id: 1) }
    second = execute_request(subject: user_b) { success_payload(id: 2) }

    expect(first.payload.fetch(:data)).to eq(id: 1)
    expect(second.payload.fetch(:data)).to eq(id: 2)
    expect(IdempotencyKey.count).to eq(2)
  end

  it 'allows the same key on different endpoints because the scope is operation-specific' do
    first = execute_request(scope: 'users.logout') { success_payload(ok: true) }
    second = execute_request(scope: 'payments.capture') { success_payload(ok: true) }

    expect(first.replayed).to be(false)
    expect(second.replayed).to be(false)
    expect(IdempotencyKey.count).to eq(2)
  end

  it 'rejects invalid keys and oversized keys' do
    expect do
      execute_request(key: 'bad key') { success_payload }
    end.to raise_error(InvalidIdempotencyKeyError)

    expect do
      execute_request(key: 'a' * 129) { success_payload }
    end.to raise_error(InvalidIdempotencyKeyError)
  end

  it 'replays completed requests until they expire' do
    first = execute_request { success_payload(ok: true) }
    second = execute_request { raise 'should not execute' }

    expect(first.replayed).to be(false)
    expect(second.replayed).to be(true)
  end

  it 'allows an expired idempotency record to be claimed again' do
    record = create(
      :idempotency_key,
      :completed,
      idempotency_scope: 'foundation.mutation',
      key_digest: Digest::SHA256.hexdigest('request-key-123'),
      request_fingerprint: 'fingerprint-a',
      expires_at: 1.minute.ago
    )

    result = execute_request { success_payload(replayed: false) }

    expect(result.replayed).to be(false)
    expect(record.reload).to be_completed
    expect(record.expires_at).to be > Time.current
  end

  it 'returns a conflict when the fingerprint changes' do
    execute_request { success_payload(ok: true) }

    expect do
      execute_request(
        request_context: {
          method: 'POST',
          path: '/foundation/mutation',
          fingerprint: 'fingerprint-b',
          operation: -> { success_payload(ok: false) }
        }
      )
    end.to raise_error(IdempotencyConflictError)
  end
end
