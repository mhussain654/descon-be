# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::BaseController, type: :controller do
  controller(described_class) do
    before_action :authenticate_current_user!

    def insecure
      render_success(data: { ok: true })
    end
  end

  before do
    ensure_staff_authorization_reference_data!

    routes.draw do
      get 'insecure' => 'api/v1/base#insecure'
    end
  end

  it 'raises when a protected action forgets to authorize' do
    user = create(:user, role: 'admin', email: 'controller-missing-authorize@example.com', password: 'Password123!')
    session = create(:session, user:)
    token = Authentication::TokenIssuer.call(user:, session:)

    request.headers['Authorization'] = "Bearer #{token}"

    expect { get :insecure }.to raise_error(Pundit::AuthorizationNotPerformedError)
  end
end
