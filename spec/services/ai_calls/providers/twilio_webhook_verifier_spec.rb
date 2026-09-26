# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Providers::TwilioWebhookVerifier do
  let(:auth_token) { 'auth-token' }
  let(:configuration) { instance_double(AiCalls::Configuration, twilio_auth_token: auth_token) }
  let(:verifier) { described_class.new(configuration:) }

  let(:url) { 'https://descon.example.test/api/v1/ai_calls/elevenlabs/webhooks/post_call' }
  let(:params) { { 'To' => '+18005551212', 'CallSid' => 'CA1234567890', 'From' => '+14158675310' } }

  def expected_signature(url:, params:, secret: auth_token)
    sorted_param_string = params.sort.map { |key, value| "#{key}#{value}" }.join
    digest = OpenSSL::HMAC.digest('SHA1', secret, url + sorted_param_string)
    Base64.strict_encode64(digest)
  end

  describe '#valid?' do
    it 'accepts a correctly computed signature regardless of param insertion order' do
      signature = expected_signature(url:, params:)

      expect(verifier.valid?(signature:, url:, params:)).to be(true)
      expect(verifier.valid?(signature:, url:, params: params.to_a.reverse.to_h)).to be(true)
    end

    it 'rejects an incorrect signature' do
      expect(verifier.valid?(signature: 'invalid-signature', url:, params:)).to be(false)
    end

    it 'rejects a signature computed with the wrong auth token' do
      signature = expected_signature(url:, params:, secret: 'wrong-token')

      expect(verifier.valid?(signature:, url:, params:)).to be(false)
    end

    it 'rejects a signature computed for a different url or params' do
      signature = expected_signature(url:, params:)

      expect(verifier.valid?(signature:, url: "#{url}?tampered=1", params:)).to be(false)
      expect(verifier.valid?(signature:, url:, params: params.merge('Digits' => '1234'))).to be(false)
    end

    it 'rejects when no auth token is configured' do
      unconfigured = described_class.new(configuration: instance_double(AiCalls::Configuration, twilio_auth_token: nil))
      signature = expected_signature(url:, params:)

      expect(unconfigured.valid?(signature:, url:, params:)).to be(false)
    end

    it 'rejects a blank signature' do
      expect(verifier.valid?(signature: '', url:, params:)).to be(false)
      expect(verifier.valid?(signature: nil, url:, params:)).to be(false)
    end
  end

  describe '#verify!' do
    it 'raises on an invalid signature and returns nil on a valid one' do
      signature = expected_signature(url:, params:)

      expect(verifier.verify!(signature:, url:, params:)).to be_nil
      expect do
        verifier.verify!(signature: 'invalid-signature', url:, params:)
      end.to raise_error(AiCallSignatureInvalidError)
    end
  end
end
