# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Communication, type: :model do
  subject(:communication) { build(:communication) }

  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:initiated_by).class_name('User').optional }

  it 'normalizes channel and locale codes' do
    communication.channel_code = ' SMS '
    communication.direction_code = ' OUTBOUND '
    communication.status_code = ' SENT '
    communication.locale = ' UR '
    communication.validate

    expect(communication.channel_code).to eq('sms')
    expect(communication.direction_code).to eq('outbound')
    expect(communication.status_code).to eq('sent')
    expect(communication.locale).to eq('ur')
  end

  it 'rejects unsupported locales' do
    communication.locale = 'fr'

    expect(communication).not_to be_valid
  end
end
