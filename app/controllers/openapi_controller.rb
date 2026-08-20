# frozen_string_literal: true

class OpenapiController < ApplicationController
  def show
    send_file Rails.root.join('openapi', 'openapi.yaml'),
              type: 'application/yaml; charset=utf-8',
              disposition: 'inline'
  end
end
