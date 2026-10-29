# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Payment Vouchers', type: :request do
  before { ensure_canonical_workflow_stages! }

  let(:candidate) { create(:candidate, status_code: 'fee_pending') }
  let(:assignment) do
    create(:candidate_assignment, candidate:, current_workflow_stage: WorkflowStage.find_by!(code: 'fee_pending'),
                                  onboarding_fee_amount: '1500')
  end

  def candidate_headers(extra = {})
    session = create(:candidate_session, candidate:)
    { 'Authorization' => "Bearer #{CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session: session)}" }
      .merge(extra)
  end

  def ready_for_payment
    create_all_verified_required_documents(assignment:)
  end

  def post_voucher(key = SecureRandom.uuid)
    post '/api/v1/candidate/payment/voucher', headers: candidate_headers('Idempotency-Key' => key)
  end

  describe 'POST /api/v1/candidate/payment/voucher' do
    it 'gives the candidate a payment code for their fee and saves that they chose it' do
      ready_for_payment
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(voucher_number: '0000832249220')

        post_voucher

        expect(response).to have_http_status(:created)
        data = response.parsed_body['data']
        expect(data['payment']).to include('status' => 'checkout_pending', 'provider' => 'kuickpay_voucher',
                                           'voucher_number' => '0000832249220', 'amount' => '1500.0')
        expect(data['payment']['checkout_expires_at']).to be_present
        expect(data['eligibility']['open_voucher']).to include('voucher_number' => '0000832249220')
        expect(Payment.last).to have_attributes(voucher_number: '0000832249220', amount: BigDecimal('1500'))
        expect(PaymentEvent.where(event_type: 'voucher_created').count).to eq(1)
        expect(AuditEvent.where(action_code: 'candidate_payment_checkout_initiated').count).to eq(1)
      end
    end

    it 'returns the same code, not a second one, when asked again' do
      ready_for_payment
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid

        post_voucher('key-1')
        first_id = response.parsed_body.dig('data', 'payment', 'id')
        post_voucher('key-2')

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig('data', 'payment', 'id')).to eq(first_id)
        expect(Payment.count).to eq(1)
      end
    end

    it 'lets the candidate start a card checkout while a code is open, and both stay open' do
      ready_for_payment
      with_kuickpay_configured do
        with_kuickpay_voucher_configured do
          stub_kuickpay_hybrid
          post_voucher
          stub_kuickpay_create_session

          post '/api/v1/candidate/payment', headers: candidate_headers('Idempotency-Key' => 'card-1')

          expect(response).to have_http_status(:created)
          expect(Payment.pluck(:provider_code)).to contain_exactly('kuickpay_voucher', 'kuickpay')
          expect(response.parsed_body.dig('data', 'eligibility')).to include('card_checkout_open' => true)
          expect(response.parsed_body.dig('data', 'eligibility', 'open_voucher', 'voucher_number'))
            .to eq('0000832249220')
        end
      end
    end

    it 'lets the candidate get a code while a card checkout is open' do
      ready_for_payment
      with_kuickpay_configured do
        with_kuickpay_voucher_configured do
          stub_kuickpay_create_session
          post '/api/v1/candidate/payment', headers: candidate_headers('Idempotency-Key' => 'card-1')
          expect(response).to have_http_status(:created)
          stub_kuickpay_hybrid

          post_voucher

          expect(response).to have_http_status(:created)
          expect(response.parsed_body.dig('data', 'payment', 'provider')).to eq('kuickpay_voucher')
          expect(response.parsed_body.dig('data', 'eligibility', 'card_checkout_open')).to be(true)
        end
      end
    end

    it 'allows a new code once the old one has expired' do
      ready_for_payment
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(voucher_number: '0000811111')
        post_voucher
        Payment.last.update!(checkout_expires_at: 1.hour.ago)
        stub_kuickpay_hybrid(voucher_number: '0000822222')

        post_voucher

        expect(response).to have_http_status(:created)
        expect(Payment.pluck(:voucher_number)).to contain_exactly('0000811111', '0000822222')
      end
    end

    it 'is not available before the fee stage' do
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid
        early = create(:candidate, status_code: 'documents_uploaded')
        create(:candidate_assignment, candidate: early,
                                      current_workflow_stage: WorkflowStage.find_by!(code: 'documents_uploaded'))
        session = create(:candidate_session, candidate: early)
        token = CandidateAuthentication::TokenIssuer.call(candidate: early, candidate_session: session)

        post '/api/v1/candidate/payment/voucher',
             headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'k' }

        expect(response).to have_http_status(:unprocessable_content)
        expect(Payment.count).to eq(0)
      end
    end

    it 'is unavailable when voucher payments are switched off' do
      ready_for_payment

      post_voucher

      expect(response).to have_http_status(:service_unavailable)
      expect(Payment.count).to eq(0)
    end

    it 'is unavailable when an admin switches payment codes off in App Settings' do
      ready_for_payment
      AppFeatureSetting.current.update!(voucher_payment_enabled: false)
      with_kuickpay_voucher_configured do
        post_voucher

        expect(response).to have_http_status(:service_unavailable)
        expect(Payment.count).to eq(0)
      end
    end

    it 'refuses a card checkout when an admin switches card payment off in App Settings' do
      ready_for_payment
      AppFeatureSetting.current.update!(card_payment_enabled: false)
      with_kuickpay_configured do
        post '/api/v1/candidate/payment', headers: candidate_headers('Idempotency-Key' => 'card-off')

        expect(response).to have_http_status(:service_unavailable)
        expect(Payment.count).to eq(0)
      end
    end

    it 'leaves nothing behind when KuickPay refuses' do
      ready_for_payment
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(insert_code: '05')

        post_voucher

        expect(response).to have_http_status(:service_unavailable)
        expect(Payment.count).to eq(0)
      end
    end

    it 'requires an Idempotency-Key and a signed-in candidate' do
      ready_for_payment
      post '/api/v1/candidate/payment/voucher', headers: candidate_headers
      expect(response).to have_http_status(:bad_request)

      post '/api/v1/candidate/payment/voucher'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/candidate/payment' do
    it 'says whether a code can be had, and shows the open code and whether a card checkout is open' do
      ready_for_payment
      with_kuickpay_voucher_configured do
        get '/api/v1/candidate/payment', headers: candidate_headers
        expect(response.parsed_body['data']).to include('voucher_available' => true, 'open_voucher' => nil,
                                                        'card_checkout_open' => false)

        stub_kuickpay_hybrid
        post_voucher
        get '/api/v1/candidate/payment', headers: candidate_headers
        expect(response.parsed_body['data']['open_voucher']).to include('provider' => 'kuickpay_voucher')
      end
    end

    it 'hides payment codes, even an open one, once an admin switches them off' do
      ready_for_payment
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid
        post_voucher
        AppFeatureSetting.current.update!(voucher_payment_enabled: false)

        get '/api/v1/candidate/payment', headers: candidate_headers

        expect(response.parsed_body['data']).to include('voucher_available' => false, 'open_voucher' => nil)
      end
    end

    it 'hides card payment, even an open checkout, once an admin switches it off' do
      ready_for_payment
      with_kuickpay_configured do
        stub_kuickpay_create_session
        post '/api/v1/candidate/payment', headers: candidate_headers('Idempotency-Key' => 'card-open')
        AppFeatureSetting.current.update!(card_payment_enabled: false)

        get '/api/v1/candidate/payment', headers: candidate_headers

        expect(response.parsed_body['data']).to include('checkout_available' => false, 'card_checkout_open' => false)
      end
    end

    it 'does not offer a code when voucher payments are off' do
      ready_for_payment

      get '/api/v1/candidate/payment', headers: candidate_headers

      expect(response.parsed_body['data']).to include('voucher_available' => false)
    end
  end
end
