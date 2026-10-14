# frozen_string_literal: true

require_relative '../required_env_names'

# Release steps specific to this application: protected environment loading,
# readiness checks, database preparation, and a health-gated activation that
# restores the previous release if the new one does not come up.
namespace :deploy do
  desc 'Install the environment-file loader into shared/bin'
  task :install_env_wrapper do
    on release_roles(:app) do
      wrapper = fetch(:env_wrapper_path)
      execute :mkdir, '-p', wrapper.dirname
      upload! File.expand_path('../../../deploy/bin/with-env', __dir__), wrapper.to_s
      execute :chmod, '0755', wrapper
    end
  end

  desc 'Fail early, by variable name, if the environment file lacks values the application needs'
  task :check_env_file do
    next if fetch(:skip_env_check, false)

    on primary(:app) do
      file = fetch(:env_file_path).to_s
      unless test('[', '-f', file, ']')
        raise "#{file} does not exist on the server. Create it from deploy/shared.env.example " \
              '(mode 0600, owned by deploy) and run the deploy again.'
      end

      # Names only: grep keeps lines with a non-empty value and `cut` drops the
      # value, so no secret is ever read into this process or printed. A
      # DB_HOST of localhost is treated as unset (it is the silent default).
      listing = capture(
        "grep -E '^[A-Za-z_][A-Za-z0-9_]*=.' #{file.shellescape} " \
        "| grep -vE '^DB_HOST=(localhost|127\\.0\\.1|::1)$' | cut -d= -f1",
        raise_on_non_zero_exit: false
      )
      missing = DesconDeploy::REQUIRED_ENV_NAMES - listing.split
      next if missing.empty?

      raise "The environment file #{file} on the server is missing or has empty values for:\n" \
            "#{missing.map { |name| "  - #{name}" }.join("\n")}\n" \
            '(DB_HOST also counts as missing when it is localhost.) ' \
            'Add them (see deploy/shared.env.example) and run the deploy again; nothing was changed on the server.'
    end
  end

  # Rails commands run by Capistrano get the same protected environment file
  # the systemd unit uses, without relying on any shell profile. The file is
  # named explicitly so the wrapper can never read a different one than
  # `deploy:check_env_file` just verified.
  task :map_env_wrapper do
    SSHKit.config.default_env[:descon_env_file] = fetch(:env_file_path).to_s
    %i[rake rails].each do |command|
      SSHKit.config.command_map.prefix[command].unshift(fetch(:env_wrapper_path).to_s)
    end
  end

  desc 'Read-only environment readiness report (databases/TLS, pg_dump, S3, scanner)'
  task :preflight do
    next if fetch(:rehearsal, false)

    on primary(:app) do
      within release_path do
        execute :rake, 'deployment:preflight'
      end
    end
  end

  desc 'Create/migrate all four databases (primary, cache, queue, cable); seeds a new database once'
  task :db_prepare do
    next if fetch(:rehearsal, false)

    on primary(:db) do
      migrate_env_file = shared_path.join('.env.migrate')
      within release_path do
        env = { db_statement_timeout_ms: '0' }
        # Optional separate migration role: if shared/.env.migrate exists it
        # supplies DB_USERNAME/DB_PASSWORD for this command only.
        env[:descon_env_override_file] = migrate_env_file.to_s if test('[', '-f', migrate_env_file.to_s, ']')
        with env do
          execute :rake, 'db:prepare'
        end
      end
    end
  end

  # Records the release `current` points at BEFORE the new one replaces it:
  # that, not "the newest other directory", is what a failed deploy restores
  # (failed releases are deleted, but this keeps the choice exact).
  desc 'Remember which release is serving before the new release is linked'
  task :remember_serving_release do
    on primary(:app) do
      serving = capture(:readlink, current_path, raise_on_non_zero_exit: false).to_s.strip
      set :serving_release, serving.empty? ? nil : File.basename(serving)
    end
  end

  desc 'Restart the API on the new release; restore the previous release if it does not become healthy'
  task :activate do
    rolling_back = Rake.application.top_level_tasks.include?('deploy:rollback')

    on primary(:app) do
      restart = -> { execute(*fetch(:service_restart_command).to_s.split) }
      healthy = lambda do
        fetch(:health_check_attempts).times do
          return true if test(*fetch(:health_check_command))

          sleep fetch(:health_check_interval_seconds)
        end
        false
      end

      reason = begin
        restart.call
        healthy.call ? nil : 'the new release did not become healthy'
      rescue SSHKit::Command::Failed => e
        "restarting the service failed (#{e.message.to_s.lines.first.to_s.strip})"
      end
      next if reason.nil?

      error "deploy:activate -- #{reason}"
      raise reason if rolling_back

      failed_release = release_path.basename.to_s
      previous = fetch(:serving_release)
      raise "#{reason}; there was no previous release to restore" if previous.nil?

      # Same portable rename Capistrano's own symlink:release uses: create the
      # link beside the releases, then rename it over `current` atomically.
      begin
        staged_link = releases_path.join(current_path.basename)
        execute :ln, '-sfn', releases_path.join(previous), staged_link
        execute :mv, '-f', staged_link, current_path.parent
      rescue SSHKit::Command::Failed => e
        raise "#{reason}; RESTORING #{previous} FAILED (#{e.message.to_s.lines.first.to_s.strip}) -- " \
              "`current` still points at #{failed_release}. Fix it by hand now."
      end

      restored = begin
        restart.call
        healthy.call
      rescue SSHKit::Command::Failed
        false
      end
      # The failed release is reproducible from its commit and its logs are in
      # the journal; leaving it would let a later failure "restore" onto it.
      execute :rm, '-rf', release_path if restored
      outcome = restored ? 'and is healthy' : 'but is NOT healthy -- investigate immediately'
      raise "#{reason}; previous release #{previous} was restored #{outcome}"
    end
  end

  desc 'Solid Queue processes alive on the live release (run after a deploy)'
  task :queue_status do
    on primary(:app) do
      within current_path do
        execute :rake, 'deployment:queue_status'
      end
    end
  end

  desc 'Upload, read, sign, refuse-unsigned and delete one throwaway S3 object through the live release'
  task :storage_round_trip do
    on primary(:app) do
      within current_path do
        execute :rake, 'deployment:storage_round_trip'
      end
    end
  end
end

Capistrano::DSL.stages.each do |stage|
  after stage, 'deploy:map_env_wrapper'
end
