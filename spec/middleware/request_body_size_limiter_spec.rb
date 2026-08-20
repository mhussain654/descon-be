# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RequestBodySizeLimiter do
  let(:downstream_app) { ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{}']] } }
  let(:middleware) { described_class.new(downstream_app, max_body_size: 5) }

  it 'blocks oversized requests' do
    status, = middleware.call('CONTENT_LENGTH' => '6')

    expect(status).to eq(413)
  end

  it 'allows requests without content length' do
    status, = middleware.call({})

    expect(status).to eq(200)
  end

  it 'allows malformed content length values through' do
    status, = middleware.call('CONTENT_LENGTH' => 'abc')

    expect(status).to eq(200)
  end
end
