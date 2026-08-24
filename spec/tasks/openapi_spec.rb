# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'openapi:validate rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task['openapi:validate'].reenable
  end

  it 'validates the committed OpenAPI document without raising' do
    expect { Rake::Task['openapi:validate'].invoke }.not_to raise_error
  end

  it 'prints a confirmation message' do
    expect { Rake::Task['openapi:validate'].invoke }.to output(/OpenAPI document is valid/).to_stdout
  end

  it 'raises when the document has a dangling $ref (strict_reference_validation)' do
    allow(YAML).to receive(:load_file).and_return(
      {
        'openapi' => '3.1.0',
        'info' => { 'title' => 'Invalid', 'version' => '1.0.0' },
        'paths' => {
          '/broken' => {
            'get' => {
              'responses' => {
                '200' => {
                  'description' => 'Broken response',
                  'content' => {
                    'application/json' => {
                      'schema' => { '$ref' => '#/components/schemas/DoesNotExist' }
                    }
                  }
                }
              }
            }
          }
        }
      }
    )

    expect { Rake::Task['openapi:validate'].invoke }.to raise_error(OpenAPIParser::OpenAPIError)
  end
end
