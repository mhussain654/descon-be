# frozen_string_literal: true

source 'https://rubygems.org'

gem 'aws-sdk-s3'
gem 'aws-sdk-textract'
gem 'bcrypt'
gem 'caxlsx'
gem 'csv'
gem 'devise'
gem 'jwt'
gem 'matrix'
gem 'oj'
gem 'pagy'
gem 'pg', '~> 1.1'
gem 'prawn'
gem 'prawn-table'
gem 'puma', '>= 5.0'
gem 'pundit'
gem 'rack-attack'
gem 'rack-cors'
gem 'rails', '~> 8.1.3', '>= 8.1.3.1'
gem 'sentry-rails'
gem 'sentry-ruby'

gem 'tzinfo-data', platforms: %i[windows jruby]

gem 'bootsnap', require: false
gem 'solid_cable'
gem 'solid_cache'
gem 'solid_queue'

group :development, :test do
  gem 'brakeman', '>= 8.1.0', require: false
  gem 'bullet'
  gem 'bundler-audit', require: false
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'
  gem 'dotenv-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'openapi_parser'
  gem 'rspec-rails'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'shoulda-matchers'
end

group :test do
  gem 'simplecov', require: false
  gem 'vcr'
  gem 'webmock'
end

# Deployment tooling only (Capistrano, run from an administrator's machine or
# from the deploy user on the server). Never installed in the production
# bundle: config/deploy.rb sets `bundle_without` to include `deploy`.
group :deploy do
  gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0', require: false
  gem 'capistrano', '~> 3.20', require: false
  gem 'capistrano-bundler', '~> 2.2', require: false
  gem 'capistrano-rbenv', '~> 2.2', require: false
  gem 'ed25519', '>= 1.2', '< 2.0', require: false
end
