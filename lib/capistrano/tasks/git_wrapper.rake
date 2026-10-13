# frozen_string_literal: true

# Capistrano's stock git wrapper passes `StrictHostKeyChecking=no`, which would
# accept any host key for github.com. This replacement keeps strict checking
# and never prompts: GitHub's host key must already be in the deploy user's
# known_hosts (the one-time `git ls-remote` check in the runbook does that).
Rake::Task['git:wrapper'].clear

namespace :git do
  desc 'Upload a git SSH wrapper that verifies the remote host key'
  task :wrapper do
    on release_roles(:all) do
      execute :mkdir, '-p', File.dirname(fetch(:git_wrapper_path)).shellescape
      upload! StringIO.new(<<~SCRIPT), fetch(:git_wrapper_path)
        #!/bin/sh -e
        exec /usr/bin/env ssh -o BatchMode=yes -o PasswordAuthentication=no -o StrictHostKeyChecking=yes "$@"
      SCRIPT
      execute :chmod, '700', fetch(:git_wrapper_path).shellescape
    end
  end
end
