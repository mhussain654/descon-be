# frozen_string_literal: true

# The single EC2 instance. The Elastic IP is the only address today; when a
# domain exists, DEPLOY_HOST can stay the IP (SSH) -- nothing here depends on
# the public hostname. Public URLs live in the instance's environment file and
# the frontend build (see docs/deployment/aws-ec2-runbook.md, "Adding a domain").
server ENV.fetch('DEPLOY_HOST', '52.221.51.231'), user: 'deploy', roles: %w[app db web]

set :ssh_options,
    forward_agent: false,
    auth_methods: %w[publickey],
    verify_host_key: :always

# Continuous delivery runs the same tasks on the instance itself, started by
# AWS SSM Run Command (deploy/bin/descon-deploy), so no inbound SSH is needed.
if ENV['DEPLOY_LOCAL'] == '1'
  set :sshkit_backend, SSHKit::Backend::Local
  # `bundle exec cap` leaves BUNDLE_GEMFILE/RUBYOPT in this process's
  # environment; the release's own `bundle` commands must not inherit them.
  ENV.replace(Bundler.unbundled_env)
end
