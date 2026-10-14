# frozen_string_literal: true

# Rehearses the real deploy.rb (hooks, lock, rollback, rbenv/bundler chain)
# against a temporary directory on this machine -- no server, no sudo, no
# systemd. Set REHEARSAL_ROOT to an empty directory and DEPLOY_REPO_URL to a
# local git path. Rails-level tasks (preflight, db:prepare) are skipped here;
# they need a production-shaped environment and are exercised separately (see
# docs/deployment/aws-ec2-runbook.md, "Rehearsing locally").
root = ENV.fetch('REHEARSAL_ROOT')

server 'localhost', user: ENV.fetch('USER'), roles: %w[app db web]
set :sshkit_backend, SSHKit::Backend::Local
# See config/deploy/production.rb: keep this process's Bundler environment out of the release's commands.
ENV.replace(Bundler.unbundled_env)

set :deploy_to, "#{root}/var-www/descon-mps-api"
set :rbenv_custom_path, "#{root}/rbenv"
set :deploy_lock_dir, "#{root}/locks/descon-mps.lock"
set :default_env, { 'RAILS_ENV' => 'production' }

set :rehearsal, true
set :env_file_path, "#{root}/shared.env"
fakes = File.expand_path('../../deploy/rehearsal', __dir__)
set :service_restart_command, "#{fakes}/fake-systemctl"
set :health_check_command, ["#{fakes}/fake-health"]
set :health_check_attempts, 3
set :service_status_command, %w[echo fake-service-status: inactive]
set :health_check_interval_seconds, 0
