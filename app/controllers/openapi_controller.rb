# frozen_string_literal: true

# Serves the raw OpenAPI specification file so API consumers/tooling can fetch the API contract.
class OpenapiController < ApplicationController
  # Streams the openapi.yaml file back to the caller for inline viewing.
  def show
    send_file Rails.root.join('openapi/openapi.yaml'),
              type: 'application/yaml; charset=utf-8',
              disposition: 'inline'
  end
end
