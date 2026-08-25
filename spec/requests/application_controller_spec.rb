# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ApplicationController behavior', type: :request do
  before do
    ensure_staff_authorization_reference_data!

    stub_const('FoundationValidationModel', Class.new do
      include ActiveModel::Model

      attr_accessor :email

      validates :email, presence: true
    end)

    stub_const('FoundationTestController', Class.new(ApplicationController) do
      def invalid
        record = FoundationValidationModel.new
        record.validate
        raise ActiveRecord::RecordInvalid, record
      end

      def invalid_in_urdu
        record = FoundationValidationModel.new
        record.validate
        raise ActiveRecord::RecordInvalid, record
      end

      def missing
        raise ActiveRecord::RecordNotFound
      end

      def forbidden
        raise Pundit::NotAuthorizedError
      end

      def explode
        raise ArgumentError, 'unsafe internal detail'
      end
    end)

    stub_const('FoundationProtectedTestController', Class.new(Api::V1::BaseController) do
      before_action :authenticate_current_user!

      def insecure
        render_success(data: { ok: true })
      end
    end)
  end

  around do |example|
    with_routing do |set|
      set.draw do
        post '/foundation-test/invalid', to: 'foundation_test#invalid'
        post '/foundation-test/invalid-in-urdu', to: 'foundation_test#invalid_in_urdu'
        get '/foundation-test/missing', to: 'foundation_test#missing'
        get '/foundation-test/forbidden', to: 'foundation_test#forbidden'
        get '/foundation-test/explode', to: 'foundation_test#explode'
        get '/foundation-protected-test/insecure', to: 'foundation_protected_test#insecure'
      end

      example.run
    end
  end

  it 'renders validation errors through the shared API envelope' do
    post '/foundation-test/invalid'

    expect(response).to have_http_status(422)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('validation_failed')
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('email')
  end

  it 'localizes validation error messages in Urdu' do
    post '/foundation-test/invalid-in-urdu', headers: { 'X-Locale' => 'ur' }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.headers['Content-Language']).to eq('ur')
    expect(response.parsed_body.dig('errors', 0, 'message')).to be_present
  end

  it 'renders not found errors through the shared API envelope' do
    get '/foundation-test/missing'

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('not_found')
  end

  it 'renders authorization failures through the shared API envelope' do
    get '/foundation-test/forbidden'

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
  end

  it 'renders unexpected errors safely without leaking internals' do
    log_output = []
    allow(Rails.logger).to receive(:error) { |entry| log_output << entry }

    get '/foundation-test/explode'

    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('internal_server_error')
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq('An unexpected error occurred.')
    expect(response.body).not_to include('unsafe internal detail')
    expect(response.body).not_to include('ArgumentError')
    expect(log_output.join).not_to include('unsafe internal detail')
  end

  it 'fails a protected staff action that forgets to authorize' do
    user = create(:user, role: 'admin', email: 'missing-authorize@example.com', password: 'Password123!')
    session = create(:session, user:)
    token = Authentication::TokenIssuer.call(user:, session:)

    expect do
      get '/foundation-protected-test/insecure', headers: { 'Authorization' => "Bearer #{token}" }
    end.to raise_error(Pundit::AuthorizationNotPerformedError)
  end
end
