# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Health Ready', type: :request do
  it 'returns a generic service unavailable error when the primary database check fails' do
    connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)

    allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
    allow(connection).to receive(:execute).and_raise(ActiveRecord::StatementInvalid.new('boom'))

    get '/api/v1/health/ready'

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Service is temporarily unavailable.')
  end

  it 'fails readiness when the queue database dependency is unavailable' do
    queue_connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)

    allow(SolidQueue::Record).to receive(:connection).and_return(queue_connection)
    allow(queue_connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished.new('queue down'))

    get '/api/v1/health/ready'

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('service_unavailable')
  end
end
