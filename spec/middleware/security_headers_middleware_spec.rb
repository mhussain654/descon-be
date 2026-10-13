# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SecurityHeadersMiddleware do
  let(:app) { ->(_env) { [200, { 'content-type' => 'application/pdf' }, ['%PDF']] } }
  let(:middleware) { described_class.new(app) }

  def headers_for(path)
    _status, headers, _body = middleware.call(Rack::MockRequest.env_for(path))
    headers.transform_keys(&:downcase)
  end

  before { allow(Rails.application.config.x).to receive(:trusted_frontend_origins).and_return(%w[https://admin.example.test]) }

  it 'denies framing for API responses' do
    headers = headers_for('/api/v1/admin/candidates')

    expect(headers).to include('x-frame-options' => 'DENY', 'x-content-type-options' => 'nosniff')
    expect(headers).not_to have_key('content-security-policy')
  end

  it 'lets only the trusted frontends frame a signed file preview, so PDFs render inline' do
    headers = headers_for('/rails/active_storage/blobs/proxy/signed-id/passport.pdf')

    expect(headers).not_to have_key('x-frame-options')
    expect(headers['content-security-policy']).to eq("frame-ancestors 'self' https://admin.example.test")
    expect(headers['x-content-type-options']).to eq('nosniff')
  end
end
