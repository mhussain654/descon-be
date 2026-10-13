# frozen_string_literal: true

require 'open3'

module Deployment
  # The database half of Deployment::PreflightCheck: all four databases
  # (primary, Solid Cache, Solid Queue, Solid Cable) reachable, TLS in use with
  # the server certificate verified when the database is remote and this is a
  # production process, and a `pg_dump` at least as new as the server (the
  # nightly backup job shells out to it, and pg_dump refuses a newer server).
  class DatabaseReadinessCheck < ApplicationService
    DATABASES = {
      'primary' => -> { ActiveRecord::Base },
      'cache' => -> { SolidCache::Record },
      'queue' => -> { SolidQueue::Record },
      'cable' => -> { SolidCable::Record }
    }.freeze

    LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
    CERTIFICATE_VERIFYING_SSLMODES = %w[verify-ca verify-full].freeze

    def call
      [*DATABASES.map { |name, record_class| database_result(name, record_class.call) }, pg_dump_result]
    end

    private

    def database_result(name, record_class)
      record_class.with_connection do |connection|
        connection.select_value('SELECT 1')
        summarize(name, connection)
      end
    rescue ActiveRecord::ActiveRecordError, PG::Error => e
      CheckResult.new(name: "#{name} database", status: :fail, detail: "unreachable (#{e.class.name})")
    end

    def summarize(name, connection)
      tls = tls_state(connection.raw_connection)
      problem = tls_problem(connection.pool.db_config.configuration_hash[:host].to_s, tls)
      detail = "PostgreSQL #{connection.select_value('SHOW server_version')}; " \
               "TLS #{tls[:protocol] || 'off'}; sslmode=#{tls[:sslmode]}"

      CheckResult.new(name: "#{name} database", status: problem ? :fail : :pass, detail: problem || detail)
    end

    def tls_state(raw)
      in_use = raw.ssl_in_use?
      { in_use:, protocol: in_use ? raw.ssl_attributes['protocol'] : nil, sslmode: raw.conninfo_hash[:sslmode].to_s }
    end

    # Certificate validation is only required where the database is remote and
    # this is a real production process: a local development database has no
    # TLS to verify.
    def tls_problem(host, tls)
      return unless Rails.env.production?
      return if local_host?(host)
      return 'TLS is not in use for a remote database' unless tls[:in_use]
      return if CERTIFICATE_VERIFYING_SSLMODES.include?(tls[:sslmode])

      "TLS is on but the server certificate is not verified (sslmode=#{tls[:sslmode]}); " \
        'set PGSSLMODE=verify-full and PGSSLROOTCERT'
    end

    def local_host?(host)
      host.blank? || host.start_with?('/') || LOCAL_HOSTS.include?(host)
    end

    def pg_dump_result
      client = pg_dump_major_version
      return CheckResult.new(name: 'pg_dump', status: :fail, detail: 'not found on PATH') if client.nil?

      server = server_major_version
      detail = "client #{client}, server #{server}"
      return CheckResult.new(name: 'pg_dump', status: :pass, detail:) if client >= server

      CheckResult.new(name: 'pg_dump', status: :fail,
                      detail: "#{detail}; pg_dump refuses a server newer than itself, so backups would fail")
    end

    def pg_dump_major_version
      stdout, _stderr, status = Open3.capture3('pg_dump', '--version')
      return unless status.success?

      stdout[/PostgreSQL\)\s+(\d+)/, 1]&.to_i
    rescue Errno::ENOENT
      nil
    end

    def server_major_version
      DATABASES.fetch('primary').call.with_connection do |connection|
        connection.select_value('SHOW server_version_num').to_i / 10_000
      end
    end
  end
end
