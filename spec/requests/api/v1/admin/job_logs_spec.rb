# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Job logs', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let(:path) { '/api/v1/admin/job_logs' }
  let(:developer) { create(:user, role: 'developer') }

  def auth_headers(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def create_job(class_name: 'CandidateSms::DeliveryJob', created_at: Time.current, scheduled_at: nil,
                 executions: 0, **attributes)
    SolidQueue::Job.create!(
      class_name:, queue_name: 'default', active_job_id: SecureRandom.uuid, scheduled_at:,
      arguments: { 'job_class' => class_name, 'executions' => executions,
                   'arguments' => [{ 'phone' => '+923001234567', 'cnic' => '35202-1234567-1' }] },
      created_at:, **attributes
    )
  end

  def fail_job(job, message: 'Gateway timed out for cnic=35202-1234567-1')
    line = Rails.root.join('app/jobs/candidate_sms/delivery_job.rb')
    SolidQueue::ReadyExecution.where(job_id: job.id).delete_all
    SolidQueue::FailedExecution.create!(
      job:, error: { 'exception_class' => 'Faraday::TimeoutError', 'message' => message,
                     'backtrace' => Array.new(40) { |i| "#{line}:#{i}" } }
    )
  end

  def claim(job)
    SolidQueue::ReadyExecution.where(job_id: job.id).delete_all
    process = SolidQueue::Process.create!(kind: 'Worker', name: "worker-#{job.id}", pid: 1,
                                          last_heartbeat_at: Time.current)
    SolidQueue::ClaimedExecution.create!(job:, process:)
  end

  def data = response.parsed_body.fetch('data')

  describe 'access' do
    it 'is forbidden to admin, HR and MPS staff' do
      %w[admin hr mps].each do |role|
        get path, headers: auth_headers(create(:user, role:))

        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'requires a staff login' do
      get path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/admin/job_logs' do
    it 'lists runs newest first with their status and every job class for the dropdown' do
      finished = create_job(created_at: 3.hours.ago, finished_at: 2.hours.ago)
      scheduled = create_job(class_name: 'Payments::IssueFeeVoucherJob', created_at: 2.hours.ago,
                             scheduled_at: 1.day.from_now)
      running = create_job(created_at: 1.hour.ago)
      claim(running)
      pending = create_job(created_at: 10.minutes.ago)

      get path, headers: auth_headers(developer)

      expect(response).to have_http_status(:ok)
      expect(data.pluck('id')).to eq([pending.id, running.id, scheduled.id, finished.id])
      expect(data.pluck('status')).to eq(%w[pending running scheduled finished])
      expect(data.first).to include('job_class' => 'CandidateSms::DeliveryJob', 'queue_name' => 'default',
                                    'attempt' => 1, 'error' => nil)
      expect(data.second['started_at']).to be_present
      expect(response.parsed_body.dig('meta', 'job_classes'))
        .to include('Candidates::Documents::ExtractDatesJob', 'Payments::IssueFeeVoucherJob',
                    'AiCalls::TriggerWorkflowStageCallJob')
      expect(response.parsed_body.dig('meta', 'job_classes')).not_to include('ApplicationJob')
    end

    it 'shows why a failed run failed, redacted and truncated, and never the job arguments' do
      job = create_job(executions: 2)
      fail_job(job, message: "Gateway timed out for cnic=35202-1234567-1 #{'x' * 2_000}")

      get path, headers: auth_headers(developer)

      row = data.first
      expect(row).to include('status' => 'failed', 'attempt' => 3)
      expect(row['failed_at']).to be_present
      expect(row.dig('error', 'exception_class')).to eq('Faraday::TimeoutError')
      expect(row.dig('error', 'message')).to start_with('Gateway timed out for cnic=[FILTERED]')
      expect(row.dig('error', 'message').length).to be <= 1_000
      expect(row.dig('error', 'backtrace').length).to eq(15)
      expect(row.dig('error', 'backtrace').first).to eq('app/jobs/candidate_sms/delivery_job.rb:0')
      expect(response.body).not_to include('arguments', '+923001234567', '35202-1234567-1')
    end

    it 'filters by job class, status and enqueued date range' do
      sms_failed = create_job(created_at: Time.zone.parse('2026-11-10 12:00'))
      fail_job(sms_failed)
      create_job(created_at: Time.zone.parse('2026-11-10 13:00'), finished_at: Time.current)
      create_job(class_name: 'Payments::IssueFeeVoucherJob', created_at: Time.zone.parse('2026-11-10 14:00'))
      create_job(created_at: Time.zone.parse('2026-11-01 12:00')).then { |job| fail_job(job) }

      get path, params: { filter: { job_class: 'CandidateSms::DeliveryJob', status: 'failed',
                                    enqueued_from: '2026-11-09', enqueued_to: '2026-11-10' } },
                headers: auth_headers(developer)

      expect(response).to have_http_status(:ok)
      expect(data.pluck('id')).to eq([sms_failed.id])
      expect(response.parsed_body.dig('meta', 'applied_filters')).to include('status' => 'failed')
    end

    it 'filters pending, running, scheduled and finished runs' do
      pending = create_job
      finished = create_job(finished_at: Time.current)
      scheduled = create_job(scheduled_at: 1.day.from_now)
      running = create_job
      claim(running)
      fail_job(create_job)
      headers = auth_headers(developer)

      { 'pending' => pending, 'finished' => finished, 'scheduled' => scheduled, 'running' => running }
        .each do |status, job|
        get path, params: { filter: { status: } }, headers: headers

        expect(data.pluck('id')).to eq([job.id]), "expected only the #{status} job"
      end
    end

    it 'paginates and caps the page size' do
      3.times { |i| create_job(created_at: i.minutes.ago) }
      headers = auth_headers(developer)

      get path, params: { page: { number: 2, size: 2 } }, headers: headers

      expect(data.length).to eq(1)
      expect(response.parsed_body.dig('meta', 'pagination'))
        .to include('page' => 2, 'per_page' => 2, 'total_count' => 3, 'total_pages' => 2)

      get path, params: { page: { size: 101 } }, headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects an unknown job class, status, filter or a reversed date range' do
      headers = auth_headers(developer)
      [{ job_class: 'Kernel' }, { status: 'exploded' }, { arguments: 'x' },
       { enqueued_from: '2026-11-10', enqueued_to: '2026-11-01' }, { enqueued_from: 'yesterday' }].each do |filter|
        get path, params: { filter: }, headers: headers

        expect(response).to have_http_status(:bad_request), "expected #{filter} to be rejected"
      end
    end
  end
end
