# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Bulk Calls', type: :request do
  include ActiveJob::TestHelper

  before { ensure_staff_authorization_reference_data! }

  let(:admin) { create(:user, role: 'admin') }
  let(:finance) { create(:user, role: 'finance') }
  let(:voice) { create(:robocall_voice, name_en: 'Visa approved') }

  def login(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def headers(user, extra = {})
    { 'Authorization' => "Bearer #{login(user)}", 'Content-Type' => 'application/json' }.merge(extra)
  end

  def list_candidates(user, **query)
    get '/api/v1/admin/bulk_calls/candidates',
        params: { robocall_voice_id: voice.public_id, filter: { status: 'verified' } }.merge(query),
        headers: headers(user)
  end

  def start_batch(user, body, key: SecureRandom.uuid)
    post '/api/v1/admin/bulk_calls', params: { bulk_call: body }.to_json,
                                     headers: headers(user, 'Idempotency-Key' => key)
  end

  def start_body(**overrides)
    { robocall_voice_id: voice.public_id, workflow_stage_code: 'verified', limit: 200 }.merge(overrides)
  end

  describe 'GET /api/v1/admin/bulk_calls/candidates' do
    it 'lists the candidates at the stage with their call state, plus the totals and the batch limit' do
      called, called_assignment = candidate_at('verified', full_name: 'Already Called')
      candidate_at('verified', full_name: 'Not Yet')
      candidate_at('fee_paid', full_name: 'Elsewhere')
      call_with_voice(called_assignment, voice, outcome: 'answered', status: 'completed')

      list_candidates(admin, called: 'all')

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body['data']
      expect(rows.pluck('full_name')).to contain_exactly('Already Called', 'Not Yet')
      expect(rows.find { |row| row['id'] == called.public_id }).to include(
        'call_state' => 'called', 'last_call' => include('outcome' => 'answered')
      )
      expect(rows.find { |row| row['full_name'] == 'Not Yet' }).to include('call_state' => 'not_called',
                                                                           'last_call' => nil)
      meta = response.parsed_body['meta']
      expect(meta).to include('summary' => { 'matching' => 2, 'called' => 1, 'remaining' => 1 }, 'batch_limit' => 200,
                              'applied_filters' => { 'status' => 'verified' })
      expect(meta['pagination']).to include('total_count' => 2)
    end

    it 'shows only what is left to call by default, and masks the phone number' do
      candidate_at('verified', full_name: 'Not Yet')
      _, assignment = candidate_at('verified', full_name: 'Done')
      call_with_voice(assignment, voice)

      list_candidates(admin)

      rows = response.parsed_body['data']
      expect(rows.pluck('full_name')).to eq(['Not Yet'])
      expect(rows.first['mobile_number_masked']).to include('*')
    end

    it 'shows a candidate whose call is still queued in a batch as queued' do
      candidate, assignment = candidate_at('verified')
      create(:bulk_call_batch_item, bulk_call_batch: create(:bulk_call_batch, robocall_voice: voice),
                                    candidate:, candidate_assignment: assignment)

      list_candidates(admin, called: 'all')

      expect(response.parsed_body['data'].first['call_state']).to eq('queued')
    end

    it 'requires a stage and a known call type' do
      get '/api/v1/admin/bulk_calls/candidates', params: { robocall_voice_id: voice.public_id },
                                                 headers: headers(admin)
      expect(response).to have_http_status(:bad_request).or have_http_status(:unprocessable_content)

      get '/api/v1/admin/bulk_calls/candidates',
          params: { robocall_voice_id: SecureRandom.uuid, filter: { status: 'verified' } }, headers: headers(admin)
      expect(response).to have_http_status(:not_found)
    end

    it 'forbids staff without trigger_ai_calls' do
      list_candidates(finance)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/v1/admin/bulk_calls' do
    it 'starts a batch for the next candidates, queueing a call for each' do
      with_bulk_calling_enabled do
        Array.new(3) { candidate_at('verified') }

        expect { start_batch(admin, start_body(limit: 2)) }.to have_enqueued_job(AiCalls::PlaceBulkCallItemJob).twice

        expect(response).to have_http_status(:created)
        data = response.parsed_body['data']
        expect(data).to include('selected_count' => 2, 'requested_limit' => 2, 'workflow_stage_code' => 'verified',
                                'voice' => { 'id' => voice.public_id, 'name' => 'Visa approved' },
                                'counts' => { 'queued' => 2, 'placed' => 0, 'skipped' => 0, 'failed' => 0 })
        expect(data['created_by']).to include('id' => admin.public_id)
      end
    end

    it 'takes only those not yet called when run again, so the rest can be called in a second batch' do
      with_bulk_calling_enabled do
        Array.new(3) { candidate_at('verified') }

        start_batch(admin, start_body(limit: 2))
        start_batch(admin, start_body(limit: 2))

        expect(response.parsed_body.dig('data', 'selected_count')).to eq(1)
        expect(BulkCallBatchItem.distinct.pluck(:candidate_id).size).to eq(3)
      end
    end

    it 'replays the same response for a retried Idempotency-Key without starting a second batch' do
      with_bulk_calling_enabled do
        Array.new(3) { candidate_at('verified') }
        key = SecureRandom.uuid

        start_batch(admin, start_body, key:)
        first = response.parsed_body
        start_batch(admin, start_body, key:)

        expect(response.headers['Idempotency-Replayed']).to eq('true')
        expect(response.parsed_body['data']['id']).to eq(first['data']['id'])
        expect(BulkCallBatch.count).to eq(1)
      end
    end

    it 'requires an Idempotency-Key header' do
      with_bulk_calling_enabled do
        post '/api/v1/admin/bulk_calls', params: { bulk_call: start_body }.to_json, headers: headers(admin)

        expect(response).to have_http_status(:bad_request).or have_http_status(:unprocessable_content)
        expect(BulkCallBatch.count).to eq(0)
      end
    end

    it 'refuses a limit above the batch ceiling with a clear message' do
      with_bulk_calling_enabled do
        candidate_at('verified')

        start_batch(admin, start_body(limit: 500))

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors'].first['message']).to include('200')
      end
    end

    it 'refuses when there is nobody left to call' do
      with_bulk_calling_enabled do
        start_batch(admin, start_body)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors'].first['code']).to eq('ai_call_bulk_nothing_to_call')
      end
    end

    it 'refuses while outbound calling is switched off' do
      with_env('AI_VOICE_PROVIDER' => 'robocall', 'AI_VOICE_OUTBOUND_ENABLED' => 'false') do
        candidate_at('verified')

        start_batch(admin, start_body)

        expect(response).to have_http_status(:service_unavailable)
        expect(BulkCallBatch.count).to eq(0)
      end
    end

    it 'refuses outside the allowed calling hours, queueing nothing for later' do
      with_env('AI_VOICE_PROVIDER' => 'robocall', 'AI_VOICE_OUTBOUND_ENABLED' => 'true',
               'AI_VOICE_CALLING_HOURS_START' => '0', 'AI_VOICE_CALLING_HOURS_END' => '0') do
        candidate_at('verified')

        expect { start_batch(admin, start_body) }.not_to have_enqueued_job(AiCalls::PlaceBulkCallItemJob)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors'].first['code']).to eq('ai_call_outside_calling_hours')
        expect(BulkCallBatch.count).to eq(0)
      end
    end

    it 'refuses a batch larger than what is left of today\'s call budget' do
      with_bulk_calling_enabled do
        with_env('AI_VOICE_DAILY_OUTBOUND_CALL_LIMIT' => '1') do
          Array.new(2) { candidate_at('verified') }

          start_batch(admin, start_body)

          expect(response).to have_http_status(:too_many_requests)
          expect(BulkCallBatch.count).to eq(0)
        end
      end
    end

    it 'rejects a limit that is not a number' do
      with_bulk_calling_enabled do
        candidate_at('verified')

        start_batch(admin, start_body(limit: 'many'))

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it 'forbids staff without trigger_ai_calls' do
      with_bulk_calling_enabled do
        candidate_at('verified')

        start_batch(finance, start_body)

        expect(response).to have_http_status(:forbidden)
        expect(BulkCallBatch.count).to eq(0)
      end
    end
  end

  describe 'GET /api/v1/admin/bulk_calls' do
    it 'lists recent batches, newest first, with item counts' do
      older = create(:bulk_call_batch, robocall_voice: voice, created_at: 2.days.ago)
      newer = create(:bulk_call_batch, robocall_voice: voice)
      create(:bulk_call_batch_item, bulk_call_batch: newer, status: 'placed')
      create(:bulk_call_batch_item, bulk_call_batch: newer, status: 'queued')

      get '/api/v1/admin/bulk_calls', headers: headers(admin)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body['data']
      expect(data.pluck('id')).to eq([newer.public_id, older.public_id])
      expect(data.first['counts']).to eq('queued' => 1, 'placed' => 1, 'skipped' => 0, 'failed' => 0)
      expect(data.last['counts'].values).to all(eq(0))
    end

    it 'forbids staff without trigger_ai_calls' do
      get '/api/v1/admin/bulk_calls', headers: headers(finance)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/admin/bulk_calls/:id' do
    it 'shows the batch with each candidate\'s result and call outcome' do
      batch = create(:bulk_call_batch, robocall_voice: voice)
      placed_candidate, assignment = candidate_at('verified', full_name: 'Placed One')
      call = call_with_voice(assignment, voice, outcome: 'callback_required', status: 'completed')
      create(:bulk_call_batch_item, bulk_call_batch: batch, candidate: placed_candidate,
                                    candidate_assignment: assignment, status: 'placed', candidate_ai_call: call)
      skipped_candidate, skipped_assignment = candidate_at('verified', full_name: 'Skipped One')
      create(:bulk_call_batch_item, bulk_call_batch: batch, candidate: skipped_candidate,
                                    candidate_assignment: skipped_assignment, status: 'skipped',
                                    skip_reason: 'stage_changed')

      get "/api/v1/admin/bulk_calls/#{batch.public_id}", headers: headers(admin)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body['data']
      expect(data['counts']).to include('placed' => 1, 'skipped' => 1)
      placed = data['items'].find { |item| item['candidate']['full_name'] == 'Placed One' }
      expect(placed).to include('status' => 'placed', 'call' => include('outcome' => 'callback_required'))
      skipped = data['items'].find { |item| item['candidate']['full_name'] == 'Skipped One' }
      expect(skipped).to include('status' => 'skipped', 'skip_reason' => 'stage_changed', 'call' => nil)
    end

    it 'returns 404 for an unknown batch and forbids staff without trigger_ai_calls' do
      get "/api/v1/admin/bulk_calls/#{SecureRandom.uuid}", headers: headers(admin)
      expect(response).to have_http_status(:not_found)

      batch = create(:bulk_call_batch)
      get "/api/v1/admin/bulk_calls/#{batch.public_id}", headers: headers(finance)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
