# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Payment Corrections', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def auth_headers(user, extra = {})
    { 'Authorization' => "Bearer #{login_as(user)}" }.merge(extra)
  end

  def payment_for(**attrs)
    candidate = create(:candidate, cnic: "42101-#{format('%07d', SecureRandom.random_number(10_000_000))}-1")
    assignment = create(:candidate_assignment, candidate:,
                                               current_workflow_stage: WorkflowStage.find_by!(code: 'fee_paid'))
    create(:payment, candidate_assignment: assignment, external_reference: "EXT-#{SecureRandom.hex(4).upcase}", **attrs)
  end

  def post_correction(payment, body, headers)
    post "/api/v1/admin/payments/#{payment.public_id}/corrections", params: { correction: body }, headers:
  end

  it 'allows a finance staff member to correct a missing external_reference' do
    finance = create(:user, role: 'finance')
    payment = payment_for(external_reference: nil)

    post_correction(
      payment,
      { reason: 'Backfilling from the provider dashboard.', expected_updated_at: payment.updated_at.iso8601,
        field: 'external_reference', value: 'EXT-BACKFILL' },
      auth_headers(finance, 'Idempotency-Key' => 'correction-1')
    )

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'external_reference')).to eq('EXT-BACKFILL')
    expect(payment.reload.external_reference).to eq('EXT-BACKFILL')
  end

  it 'replays the same result for a repeated Idempotency-Key without correcting twice' do
    finance = create(:user, role: 'finance')
    payment = payment_for(external_reference: nil)
    headers = auth_headers(finance, 'Idempotency-Key' => 'correction-replay')
    body = { reason: 'Backfilling.', expected_updated_at: payment.updated_at.iso8601, field: 'external_reference',
             value: 'EXT-1' }

    post_correction(payment, body, headers)
    expect(response).to have_http_status(:created)

    expect { post_correction(payment, body, headers) }.not_to change(PaymentEvent, :count)
    expect(response).to have_http_status(:created)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
  end

  it 'requires an Idempotency-Key header' do
    finance = create(:user, role: 'finance')
    payment = payment_for(external_reference: nil)

    post_correction(
      payment,
      { reason: 'x', expected_updated_at: payment.updated_at.iso8601, field: 'external_reference', value: 'EXT-1' },
      auth_headers(finance)
    )

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_idempotency_key')
  end

  it 'forbids a staff member without manage_payments' do
    management = create(:user, role: 'management')
    payment = payment_for

    post_correction(
      payment,
      { reason: 'x', expected_updated_at: payment.updated_at.iso8601, field: 'external_reference', value: 'EXT-1' },
      auth_headers(management, 'Idempotency-Key' => 'correction-forbidden')
    )

    expect(response).to have_http_status(:forbidden)
  end

  it 'returns a conflict when the payment changed since expected_updated_at' do
    finance = create(:user, role: 'finance')
    payment = payment_for(external_reference: nil)
    stale_timestamp = payment.updated_at.iso8601
    # The staleness check truncates to whole seconds (matching
    # Admin::ReferenceData::MutationService's established convention) --
    # force real separation so this update doesn't land in the same second.
    travel_to(2.seconds.from_now) { payment.update!(note: 'touched by someone else') }

    post_correction(
      payment,
      { reason: 'x', expected_updated_at: stale_timestamp, field: 'external_reference', value: 'EXT-1' },
      auth_headers(finance, 'Idempotency-Key' => 'correction-stale')
    )

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('stale_payment')
  end

  it 'requires a reason' do
    finance = create(:user, role: 'finance')
    payment = payment_for(external_reference: nil)

    post_correction(
      payment,
      { reason: '', expected_updated_at: payment.updated_at.iso8601, field: 'external_reference', value: 'EXT-1' },
      auth_headers(finance, 'Idempotency-Key' => 'correction-no-reason')
    )

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('correction.reason')
  end

  it 'rejects a correction to an unsupported field' do
    finance = create(:user, role: 'finance')
    payment = payment_for

    post_correction(
      payment,
      { reason: 'x', expected_updated_at: payment.updated_at.iso8601, field: 'amount', value: '5000' },
      auth_headers(finance, 'Idempotency-Key' => 'correction-unsupported-field')
    )

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('payment_correction_not_allowed')
  end

  it 'returns not_found for an unknown payment id' do
    finance = create(:user, role: 'finance')

    post '/api/v1/admin/payments/does-not-exist/corrections',
         params: { correction: { reason: 'x', expected_updated_at: Time.current.iso8601, field: 'external_reference',
                                 value: 'EXT-1' } },
         headers: auth_headers(finance, 'Idempotency-Key' => 'correction-not-found')

    expect(response).to have_http_status(:not_found)
  end

  it 'resolves a reconciliation finding and reflects it in the payment detail response' do
    finance = create(:user, role: 'finance')
    payment = payment_for(paid_at: nil)
    run = create(:payment_reconciliation_run)
    finding = create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment:,
                                                      finding_code: 'paid_at_missing')

    post_correction(
      payment,
      { reason: 'Confirmed paid via provider dashboard, backfilling the timestamp.',
        expected_updated_at: payment.updated_at.iso8601, finding_id: finding.public_id, field: 'paid_at',
        value: 1.day.ago.iso8601 },
      auth_headers(finance, 'Idempotency-Key' => 'correction-resolve-finding')
    )

    expect(response).to have_http_status(:created)
    resolved_finding = response.parsed_body.dig('data', 'reconciliation_findings', 0)
    expect(resolved_finding['state']).to eq('resolved')
    expect(payment.reload.paid_at).to be_present
  end
end
