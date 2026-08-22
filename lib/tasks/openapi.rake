# frozen_string_literal: true

namespace :openapi do
  desc 'Validate the OpenAPI document'
  task validate: :environment do
    document = YAML.load_file(Rails.root.join('openapi/openapi.yaml'))
    OpenAPIParser.parse(document, strict_reference_validation: true)
    puts 'OpenAPI document is valid.'
  end
end
