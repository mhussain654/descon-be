# frozen_string_literal: true

require_relative 'boot'
require_relative '../app/middleware/request_body_size_limiter'
require_relative '../app/middleware/security_headers_middleware'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_cable/engine'
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RailsApiBase
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true
    config.time_zone = 'UTC'
    config.active_record.default_timezone = :utc
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = { database: { writing: :queue } }
    config.i18n.default_locale = :en
    config.x.i18n.supported_locales =
      ENV.fetch('APP_SUPPORTED_LOCALES', 'en,ur')
         .split(',')
         .map(&:strip)
         .compact_blank
         .map { |locale| locale.tr('-', '_').downcase.to_sym }
         .append(:en)
         .uniq
    config.i18n.available_locales = config.x.i18n.supported_locales
    config.i18n.fallbacks = [:en]

    %w[errors middleware policies queries serializers services validators].each do |directory|
      path = Rails.root.join('app', directory)
      config.autoload_paths << path
      config.eager_load_paths << path
    end

    config.generators do |generator|
      generator.test_framework :rspec,
                               fixtures: false,
                               helper_specs: false,
                               routing_specs: false,
                               view_specs: false
      generator.fixture_replacement :factory_bot, dir: 'spec/factories'
    end

    config.middleware.use Rack::Attack
    config.middleware.use SecurityHeadersMiddleware
    config.middleware.use RequestBodySizeLimiter,
                          max_body_size: ENV.fetch('MAX_REQUEST_BODY_SIZE_BYTES', 5.megabytes).to_i
  end
end
