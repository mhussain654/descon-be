# frozen_string_literal: true

# One host-wide lock, taken with an atomic `mkdir`, shared by the backend and
# frontend deployments (same path in both repositories' deploy configuration)
# so the two never change the instance at the same time. A lock left behind by
# a crashed run is never broken automatically: the error names who took it.
namespace :deploy do
  desc 'Take the host-wide deployment lock (shared with the frontend deploys)'
  task :acquire_lock do
    on primary(:app) do
      lock_dir = fetch(:deploy_lock_dir)
      execute :mkdir, '-p', File.dirname(lock_dir)

      unless test(:mkdir, lock_dir)
        holder = capture(:cat, File.join(lock_dir, 'owner'), raise_on_non_zero_exit: false).to_s.strip
        holder = 'owner unknown' if holder.empty?
        raise "Another deployment holds #{lock_dir} (#{holder}). " \
              'If that run crashed, check the host and remove the directory by hand.'
      end

      set :deploy_lock_held, true
      owner = "#{fetch(:application)} by #{ENV.fetch('USER', 'unknown')} at #{Time.now.utc.iso8601}"
      execute :echo, owner.shellescape, '>', File.join(lock_dir, 'owner')
    end
  end

  desc 'Release the deployment lock this run took (never one it did not take)'
  task :release_lock do
    next unless fetch(:deploy_lock_held, false)

    on primary(:app) do
      execute :rm, '-rf', fetch(:deploy_lock_dir)
    end
    set :deploy_lock_held, false
  end
end
