# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationQuery do
  describe '#call' do
    it 'raises NotImplementedError by default' do
      expect { described_class.new.call }.to raise_error(NotImplementedError)
    end
  end
end
