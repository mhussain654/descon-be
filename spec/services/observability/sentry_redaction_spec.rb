# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Observability::SentryRedaction do
  describe '.redact_text' do
    it 'redacts a key=value pair for a sensitive field name' do
      expect(described_class.redact_text('token=abc.def.ghi rejected')).to eq('token=[FILTERED] rejected')
    end

    it 'redacts a bare JWT-shaped string even without a labeled key' do
      jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dGhpc2lzYXNpZ25hdHVyZQ'
      expect(described_class.redact_text("Bearer #{jwt}")).to eq('Bearer [FILTERED]')
    end

    it 'redacts a bare CNIC-shaped number' do
      expect(described_class.redact_text('Lookup failed for 42101-1234567-1')).to eq('Lookup failed for [FILTERED]')
    end

    it 'redacts an unformatted 13-digit CNIC' do
      expect(described_class.redact_text('cnic 4210112345671 not found')).to eq('cnic [FILTERED] not found')
    end

    it 'redacts a JSON-shaped key/value pair' do
      expect(described_class.redact_text('{"password": "hunter2"}')).to include('password=[FILTERED]')
    end

    it 'redacts compound snake_case field names, not just the bare word' do
      # The match starts at the sensitive word itself (not the whole
      # compound key), so gsub only replaces from there onward -- the
      # "access_"/"refresh_" prefix survives as harmless context, while the
      # sensitive value itself is fully redacted either way.
      expect(described_class.redact_text('access_token: abc123')).to eq('access_token=[FILTERED]')
      expect(described_class.redact_text('refresh_token=xyz789')).to eq('refresh_token=[FILTERED]')
      expect(described_class.redact_text('password_confirmation: hunter2')).to eq('password=[FILTERED]')
    end

    it 'does not redact an unrelated word that merely contains a sensitive word as a substring' do
      text = 'tokenized_value: safe'
      expect(described_class.redact_text(text)).to eq(text)
    end

    it 'leaves ordinary text untouched' do
      text = 'Failed to fetch /api/v1/candidates'
      expect(described_class.redact_text(text)).to eq(text)
    end

    it 'returns a non-string value unchanged' do
      expect(described_class.redact_text(nil)).to be_nil
      expect(described_class.redact_text(42)).to eq(42)
    end
  end

  describe '.redact_value (recursive walk)' do
    it 'redacts a string leaf nested arbitrarily deep in a hash' do
      value = { a: { b: { c: 'token=abc123' } } }

      expect(described_class.redact_value(value)).to eq(a: { b: { c: 'token=[FILTERED]' } })
    end

    it 'redacts string leaves inside an array nested inside a hash' do
      value = { queries: ['SELECT * FROM users WHERE cnic = 42101-1234567-1', 'ok'] }

      result = described_class.redact_value(value)
      expect(result[:queries][0]).to eq('SELECT * FROM users WHERE cnic=[FILTERED]')
      expect(result[:queries][1]).to eq('ok')
    end

    it 'leaves non-string leaves (numbers, booleans, nil) unchanged' do
      value = { count: 5, active: true, missing: nil }

      expect(described_class.redact_value(value)).to eq(value)
    end
  end

  describe '.redact_event' do
    def error_event
      client = Sentry::Client.new(Sentry::Configuration.new)
      Sentry::ErrorEvent.new(configuration: client.configuration)
    end

    it 'redacts the top-level event message' do
      event = error_event
      event.message = 'Login failed for cnic=42101-1234567-1'

      described_class.redact_event(event)

      expect(event.message).to eq('Login failed for cnic=[FILTERED]')
    end

    it 'redacts each exception value -- the actual capture path for an unhandled exception, unlike event.message' do
      event = error_event
      begin
        raise 'invalid otp=123456 for candidate'
      rescue StandardError => e
        event.add_exception_interface(e, mechanism: Sentry::Mechanism.new)
      end

      described_class.redact_event(event)

      expect(event.exception.values.first.value).to eq('invalid otp=[FILTERED] for candidate (RuntimeError)')
    end

    it 'redacts nested contexts' do
      event = error_event
      event.contexts = { request: { cnic: 'value looks like 42101-1234567-1' } }

      described_class.redact_event(event)

      expect(event.contexts[:request][:cnic]).to eq('value looks like [FILTERED]')
    end

    it 'redacts nested extra data' do
      event = error_event
      event.extra = { debug: { token: 'token=abc123' } }

      described_class.redact_event(event)

      expect(event.extra[:debug][:token]).to eq('token=[FILTERED]')
    end

    it 'does not raise for an event type with no #exception method (e.g. a transaction event)' do
      event = error_event
      allow(event).to receive(:respond_to?).and_call_original
      allow(event).to receive(:respond_to?).with(:exception).and_return(false)

      expect { described_class.redact_event(event) }.not_to raise_error
    end
  end

  describe '.redact_breadcrumb' do
    it 'redacts the breadcrumb message' do
      breadcrumb = Sentry::Breadcrumb.new(message: 'Request failed with password=hunter2')

      described_class.redact_breadcrumb(breadcrumb)

      expect(breadcrumb.message).to eq('Request failed with password=[FILTERED]')
    end

    it "redacts a SQL breadcrumb's bound values inside data" do
      breadcrumb = Sentry::Breadcrumb.new(
        category: 'query.active_record',
        message: 'SELECT * FROM candidates WHERE cnic = $1',
        data: { binds: ['42101-1234567-1'] }
      )

      described_class.redact_breadcrumb(breadcrumb)

      expect(breadcrumb.data[:binds]).to eq(['[FILTERED]'])
    end

    it "redacts an http breadcrumb's url query string" do
      breadcrumb = Sentry::Breadcrumb.new(category: 'httplib', data: { url: 'https://api.example.com/x?token=abc123' })

      described_class.redact_breadcrumb(breadcrumb)

      expect(breadcrumb.data[:url]).to eq('https://api.example.com/x?token=[FILTERED]')
    end

    it 'leaves an ordinary breadcrumb untouched' do
      breadcrumb = Sentry::Breadcrumb.new(category: 'navigation', message: 'visited /dashboard',
                                          data: { method: 'GET' })

      described_class.redact_breadcrumb(breadcrumb)

      expect(breadcrumb.message).to eq('visited /dashboard')
      expect(breadcrumb.data[:method]).to eq('GET')
    end
  end
end
