# frozen_string_literal: true

# Capistrano is deployment tooling only: it lives in the :deploy Bundler group,
# which the production bundle excludes (config/deploy.rb `bundle_without`).
require 'capistrano/setup'
require 'capistrano/deploy'

require 'capistrano/scm/git'
install_plugin Capistrano::SCM::Git

require 'capistrano/rbenv'
require 'capistrano/bundler'

Dir.glob('lib/capistrano/tasks/*.rake').each { |task_file| import task_file }
