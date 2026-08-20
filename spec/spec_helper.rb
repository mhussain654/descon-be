# frozen_string_literal: true

require 'simplecov' if ENV.fetch('COVERAGE', 'true') == 'true'

if defined?(SimpleCov)
  SimpleCov.start 'rails' do
    enable_coverage :branch
    minimum_coverage line: 50, branch: 15
    skip '/spec/'
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
