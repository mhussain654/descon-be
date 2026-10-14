# frozen_string_literal: true

# Backend (Rails API) deployment to the single Ubuntu EC2 instance. See
# docs/deployment/aws-ec2-runbook.md for the one-time server setup and the
# exact commands. Stages: config/deploy/production.rb (the instance),
# config/deploy/rehearsal.rb (a local rehearsal -- no server involved).
lock '~> 3.20'

set :application, 'descon-mps-api'
set :repo_url, ENV.fetch('DEPLOY_REPO_URL', 'git@github-mps-backend:mhussain654/descon-be.git')

# REVISION pins an exact commit (what CD uses, so the deployed code is the
# commit CI tested); BRANCH is for a manual deploy and defaults to main.
revision = ENV.fetch('REVISION', nil)
raise 'REVISION must be a full 40-character commit SHA' if revision && !revision.match?(/\A\h{40}\z/)

set :branch, revision || ENV.fetch('BRANCH', 'main')

set :deploy_to, '/home/deploy/descon-mps-api'
set :keep_releases, 5
set :pty, false
set :log_level, :info

# Explicit Ruby: noninteractive SSH sessions never read ~/.bashrc, so nothing
# here relies on a shell profile. The version is the repository's own.
set :rbenv_type, :user
set :rbenv_custom_path, '/home/deploy/.rbenv'
set :rbenv_ruby, File.read(File.expand_path('../.ruby-version', __dir__)).strip.delete_prefix('ruby-')

# The lockfile pins Bundler 4. The :deploy group (Capistrano itself) is not
# installed on the server's application bundle.
set :bundle_version, 4
set :bundle_without, 'development:test:deploy'
set :bundle_jobs, 2
set :bundle_flags, '--quiet'

# Production logs go to stdout (journald); only runtime state is shared.
set :linked_dirs, %w[log tmp/pids tmp/cache tmp/sockets]

# PostgreSQL 17 client tools first: the nightly backup job shells out to
# pg_dump and it must not be older than the RDS server (see the runbook).
set :default_env, {
  'RAILS_ENV' => 'production',
  'PATH' => '/usr/lib/postgresql/17/bin:$PATH'
}

# Where the protected environment file and its loader live on the server.
set :env_file_path, -> { shared_path.join('.env') }
set :env_wrapper_path, -> { shared_path.join('bin', 'with-env') }

# Host-wide deployment lock shared with the frontend repository's deploys, so
# the two never change the instance at the same time.
set :deploy_lock_dir, '/home/deploy/.deploy-locks/descon-mps.lock'

# Exact command the sudoers rule permits (deploy/sudoers/descon-mps-deploy).
set :service_restart_command, 'sudo -n /usr/bin/systemctl restart descon-mps-api.service'
set :health_check_command, %w[curl --fail --silent --max-time 5 --output /dev/null
                              http://127.0.0.1:3000/api/v1/health/ready]
set :health_check_attempts, 30
# Printed when a release fails its health check. `systemctl status` needs no
# sudo; add the deploy user to the systemd-journal group (runbook section 3.4)
# to see the log lines too.
set :service_status_command, %w[systemctl status descon-mps-api.service --no-pager --lines=40]
set :health_check_interval_seconds, 2

before 'deploy:starting', 'deploy:acquire_lock'
after 'deploy:started', 'deploy:install_env_wrapper'
after 'deploy:install_env_wrapper', 'deploy:check_env_file'
before 'deploy:updated', 'deploy:preflight'
before 'deploy:updated', 'deploy:db_prepare'
before 'deploy:symlink:release', 'deploy:remember_serving_release'
after 'deploy:publishing', 'deploy:activate'
after 'deploy:finished', 'deploy:release_lock'
after 'deploy:failed', 'deploy:release_lock'
