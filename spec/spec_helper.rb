# frozen_string_literal: true

require 'simplecov' if ENV.fetch('COVERAGE', 'true') == 'true'

if defined?(SimpleCov)
  SimpleCov.start 'rails' do
    enable_coverage :branch
    minimum_coverage line: 95
    coverage :line do
      minimum_per_file 90
    end
    skip '/spec/'

    # Documented exception (AGENTS.md: "SimpleCov per-file line coverage
    # should remain at or above 90% unless an explicitly documented
    # exception is approved" -- approved by the client, 2026-09-27):
    # lib/dev_data/** and lib/tasks/dev_data.rake are manual QA-only
    # tooling (`bin/rails dev_data:seed_qa_data`/`dev_data:clear_qa_data`),
    # invoked by a developer at the command line, never by request-serving
    # application code and never exercised by the test suite itself. They
    # carry no authentication, authorization, payment, document or workflow
    # logic -- the coverage gate this exception is carving out of is meant
    # to protect that code, not local seed scripts. Do not extend this
    # pattern to any file under app/ or to any other file under lib/
    # without the same explicit approval.
    add_filter 'lib/dev_data/'
    add_filter 'lib/tasks/dev_data.rake'
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
  config.example_status_persistence_file_path = 'tmp/rspec_examples.txt'
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
