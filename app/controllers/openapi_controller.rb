# frozen_string_literal: true

class OpenapiController < ApplicationController
  def show
    send_file openapi_spec_path,
              type: 'application/yaml; charset=utf-8',
              disposition: 'inline'
  end

  private

  def openapi_spec_path
    'openapi/openapi.yaml'
  end
end
