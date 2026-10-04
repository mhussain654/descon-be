# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::OnboardingFeePolicy do
  before { ensure_staff_authorization_reference_data! }

  it 'allows admin and finance edits, management reads, and denies HR' do
    %w[admin finance].each do |role|
      policy = described_class.new(create(:user, role:), OnboardingFeeSetting)
      expect(policy.show?).to be(true)
      expect(policy.update?).to be(true)
    end
    management = described_class.new(create(:user, role: 'management'), OnboardingFeeSetting)
    expect(management.show?).to be(true)
    expect(management.update?).to be(false)
    hr = described_class.new(create(:user, role: 'hr'), OnboardingFeeSetting)
    expect(hr.show?).to be(false)
    expect(hr.update?).to be(false)
  end
end
