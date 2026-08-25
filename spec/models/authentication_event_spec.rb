# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthenticationEvent, type: :model do
  subject(:authentication_event) { build(:authentication_event) }

  it { is_expected.to belong_to(:user).optional }
  it { is_expected.to belong_to(:session).optional }
  it { is_expected.to validate_presence_of(:event_code) }
  it { is_expected.to validate_presence_of(:occurred_at) }

  it 'validates the event code format' do
    authentication_event.event_code = 'Login Failed'

    expect(authentication_event).not_to be_valid
    expect(authentication_event.errors[:event_code]).to be_present
  end
end
