# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Onboarding Fees', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  let(:admin) { create(:user, role: 'admin') }
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }

  def headers(user = admin)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}",
      'Content-Type' => 'application/json' }
  end

  def update_fee(amount, version: 0, reason: 'Approved fee', user: admin, locale: 'en')
    assignment
    auth = headers(user).merge('X-Locale' => locale)
    patch "/api/v1/admin/candidates/#{candidate.public_id}/fee",
          params: { fee: { amount:, expected_version: version, reason: } }.to_json, headers: auth
  end

  it 'updates the default with an audit record, actor, and version' do
    patch '/api/v1/admin/onboarding_fee_setting',
          params: { fee: { amount: '26800', expected_version: 0, reason: 'New standard fee' } }.to_json,
          headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'default_amount')).to eq('26800.00')
    expect(OnboardingFeeSetting.current.updated_by).to eq(admin)
    expect(AuditEvent.find_by!(action_code: 'default_fee_updated').metadata['reason']).to eq('New standard fee')
  end

  it 'sets an override before the candidate reaches the fee stage' do
    update_fee('25000')

    expect(response).to have_http_status(:ok)
    expect(assignment.reload.onboarding_fee_amount).to eq(BigDecimal('25000'))
    expect(response.parsed_body.dig('data', 'effective_amount')).to eq('25000.00')
    expect(AuditEvent.find_by!(action_code: 'candidate_fee_updated').candidate_assignment).to eq(assignment)
  end

  it 'removes an override and follows the current default' do
    OnboardingFeeSetting.current.update!(amount: '26800')
    assignment.update!(onboarding_fee_amount: '25000')
    update_fee(nil)

    expect(response).to have_http_status(:ok)
    expect(assignment.reload.onboarding_fee_amount).to be_nil
    expect(response.parsed_body.dig('data', 'effective_amount')).to eq('26800.00')
  end

  it 'rejects a stale edit without changing the fee or auditing it' do
    assignment.update!(fee_version: 2, onboarding_fee_amount: '25000')
    expect { update_fee('26000') }.not_to change(AuditEvent, :count)

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('stale_fee')
    expect(assignment.reload.onboarding_fee_amount).to eq(BigDecimal('25000'))
  end

  it 'does not allow changing a paid fee' do
    create(:payment, candidate_assignment: assignment, amount: '25000')
    update_fee('26000')

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('fee_locked')
  end

  it 'does not allow changing an active checkout fee' do
    create(:payment, candidate_assignment: assignment, status_code: 'checkout_pending',
                     checkout_expires_at: 10.minutes.from_now)
    update_fee('26000')

    expect(response).to have_http_status(:conflict)
  end

  it 'allows changing a fee after an unpaid checkout expires' do
    create(:payment, candidate_assignment: assignment, status_code: 'checkout_pending',
                     checkout_expires_at: 1.minute.ago)
    update_fee('26000')

    expect(response).to have_http_status(:ok)
  end

  it 'rejects excess precision instead of silently rounding money' do
    update_fee('26800.001')

    expect(response).to have_http_status(:unprocessable_content)
    expect(assignment.reload.onboarding_fee_amount).to be_nil
  end

  it 'requires a reason' do
    update_fee('26000', reason: ' ')

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('fee.reason')
  end

  it 'returns localized fee validation and conflict responses in Urdu' do
    update_fee('26000', reason: ' ', locale: 'ur')

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq(
      I18n.t('api.errors.fee_reason_required', locale: :ur)
    )
    update_fee('26000', version: 99, locale: 'ur')

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.stale_fee', locale: :ur))
    expect(assignment.reload.onboarding_fee_amount).to be_nil
  end

  it 'requires payment-management permission even for staff who can edit candidates' do
    update_fee('26000', user: create(:user, role: 'hr'))

    expect(response).to have_http_status(:forbidden)
    expect(assignment.reload.onboarding_fee_amount).to be_nil
  end

  it 'allows management to read but not update the default' do
    user = create(:user, role: 'management')
    auth = headers(user)
    get '/api/v1/admin/onboarding_fee_setting', headers: auth
    expect(response).to have_http_status(:ok)

    patch '/api/v1/admin/onboarding_fee_setting',
          params: { fee: { amount: '26800', expected_version: 0, reason: 'Change' } }.to_json, headers: auth
    expect(response).to have_http_status(:forbidden)
  end

  it 'requires authentication' do
    get '/api/v1/admin/onboarding_fee_setting'

    expect(response).to have_http_status(:unauthorized)
  end
end
