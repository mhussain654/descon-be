# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ApplicationController behavior', type: :request do
  before do
    stub_const('FoundationTestController', Class.new(ApplicationController) do
      def invalid
        user = User.new
        user.validate
        raise ActiveRecord::RecordInvalid, user
      end

      def missing
        raise ActiveRecord::RecordNotFound
      end

      def forbidden
        raise Pundit::NotAuthorizedError
      end
    end)
  end

  around do |example|
    with_routing do |set|
      set.draw do
        post '/foundation-test/invalid', to: 'foundation_test#invalid'
        get '/foundation-test/missing', to: 'foundation_test#missing'
        get '/foundation-test/forbidden', to: 'foundation_test#forbidden'
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
end
