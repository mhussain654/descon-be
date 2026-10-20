# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::RobocallVoicePolicy do
  before { ensure_staff_authorization_reference_data! }

  let(:admin) { create(:user, role: 'admin') }
  let(:finance) { create(:user, role: 'finance') }

  it 'lets a permitted staff member read and change the library' do
    policy = described_class.new(admin, RobocallVoice)

    expect([policy.index?, policy.create?, policy.update?]).to all(be(true))
  end

  it 'refuses everything to staff with neither call permission' do
    policy = described_class.new(finance, RobocallVoice)

    expect([policy.index?, policy.create?, policy.update?]).to all(be(false))
  end

  it 'lets a staff member who can only trigger calls read the library but not change it' do
    trigger_only = create(:user, role: 'admin')
    allow(trigger_only).to receive(:permission?) { |code| code == 'trigger_ai_calls' }
    policy = described_class.new(trigger_only, RobocallVoice)

    expect([policy.index?, policy.create?, policy.update?]).to eq([true, false, false])
  end

  describe Admin::RobocallVoicePolicy::Scope do
    it 'resolves the voices for a permitted actor and none otherwise' do
      voice = create(:robocall_voice)

      expect(described_class.new(admin, RobocallVoice).resolve).to contain_exactly(voice)
      expect(described_class.new(finance, RobocallVoice).resolve).to be_empty
    end
  end
end
