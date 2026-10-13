# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Deployment::DatabaseReadinessCheck do
  def fake_record_class(host: 'db.internal', ssl: true, sslmode: 'verify-full', server_version_num: 170_011)
    raw = instance_double(PG::Connection, ssl_in_use?: ssl, ssl_attributes: { 'protocol' => 'TLSv1.3' },
                                          conninfo_hash: { sslmode: })
    db_config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, configuration_hash: { host: })
    pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool, db_config:)
    connection = fake_connection(raw:, pool:, server_version_num:)
    record = double('record class') # rubocop:disable RSpec/VerifiedDoubles
    allow(record).to receive(:with_connection).and_yield(connection)
    record
  end

  def fake_connection(raw:, pool:, server_version_num:)
    values = { 'SELECT 1' => 1, 'SHOW server_version' => '17.11', 'SHOW server_version_num' => server_version_num.to_s }
    connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter, raw_connection: raw, pool:)
    allow(connection).to receive(:select_value) { |sql| values.fetch(sql) }
    connection
  end

  def stub_databases(**)
    records = %w[primary cache queue cable].index_with { fake_record_class(**) }
    stub_const('Deployment::DatabaseReadinessCheck::DATABASES',
               records.transform_values { |record| -> { record } }.freeze)
  end

  def result_named(name) = described_class.call.find { |result| result.name == name }

  let(:production) { ActiveSupport::EnvironmentInquirer.new('production') }
  let(:pg_dump_status) { instance_double(Process::Status, success?: true) }

  before do
    allow(Open3).to receive(:capture3).with('pg_dump', '--version')
                                      .and_return(["pg_dump (PostgreSQL) 17.2 (Ubuntu 17.2-1)\n", '', pg_dump_status])
  end

  describe '.call' do
    context 'with the real test databases' do
      it 'reports all four databases reachable' do
        names = described_class.call.map(&:name)

        expect(names).to include('primary database', 'cache database', 'queue database', 'cable database')
        expect(described_class.call.select { |r| r.name.end_with?('database') }.map(&:status)).to all(eq(:pass))
      end
    end

    context 'when a database cannot be reached' do
      it 'fails that database without raising' do
        allow(SolidQueue::Record).to receive(:with_connection).and_raise(ActiveRecord::ConnectionNotEstablished)

        result = result_named('queue database')

        expect(result).to be_failed
        expect(result.detail).to include('unreachable (ActiveRecord::ConnectionNotEstablished)')
      end
    end

    context 'when in production against a remote database' do
      before { allow(Rails).to receive(:env).and_return(production) }

      it 'passes with TLS and a verified certificate' do
        stub_databases(sslmode: 'verify-full')

        result = result_named('primary database')

        expect(result.status).to eq(:pass)
        expect(result.detail).to include('PostgreSQL 17.11', 'TLSv1.3', 'sslmode=verify-full')
      end

      it 'fails when TLS is not in use' do
        stub_databases(ssl: false, sslmode: 'disable')

        result = result_named('primary database')

        expect(result).to be_failed
        expect(result.detail).to include('TLS is not in use')
      end

      it 'fails when TLS is on but the certificate is not verified (sslmode=require)' do
        stub_databases(sslmode: 'require')

        result = result_named('primary database')

        expect(result).to be_failed
        expect(result.detail).to include('certificate is not verified', 'PGSSLMODE=verify-full')
      end

      it 'does not demand TLS from a loopback database' do
        stub_databases(host: '127.0.0.1', ssl: false, sslmode: 'prefer')

        expect(result_named('primary database').status).to eq(:pass)
      end

      it 'does not demand TLS from a unix-socket database' do
        stub_databases(host: '/var/run/postgresql', ssl: false, sslmode: 'prefer')

        expect(result_named('primary database').status).to eq(:pass)
      end
    end

    context 'with the pg_dump client' do
      it 'passes when it is at least as new as the server' do
        stub_databases(server_version_num: 170_011)

        result = result_named('pg_dump')

        expect(result.status).to eq(:pass)
        expect(result.detail).to eq('client 17, server 17')
      end

      it 'fails when it is older than the server' do
        stub_databases(server_version_num: 170_011)
        allow(Open3).to receive(:capture3).with('pg_dump', '--version')
                                          .and_return(["pg_dump (PostgreSQL) 16.4\n", '', pg_dump_status])

        result = result_named('pg_dump')

        expect(result).to be_failed
        expect(result.detail).to include('client 16, server 17', 'backups would fail')
      end

      it 'fails when it is not installed' do
        allow(Open3).to receive(:capture3).with('pg_dump', '--version').and_raise(Errno::ENOENT)

        result = result_named('pg_dump')

        expect(result).to be_failed
        expect(result.detail).to eq('not found on PATH')
      end

      it 'fails when it exits non-zero' do
        allow(Open3).to receive(:capture3).with('pg_dump', '--version')
                                          .and_return(['', 'boom', instance_double(Process::Status, success?: false)])

        expect(result_named('pg_dump')).to be_failed
      end
    end
  end
end
