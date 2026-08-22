# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationMailer do
  it 'uses the shared mailer layout and default sender' do
    expect(described_class.default[:from]).to eq('from@example.com')
    expect(described_class._layout).to eq('mailer')
  end
end
