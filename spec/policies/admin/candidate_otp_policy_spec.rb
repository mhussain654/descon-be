# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateOtpPolicy do
  before { ensure_staff_authorization_reference_data! }

  it 'allows only the developer role' do
    expect(described_class.new(create(:user, role: 'developer'), CandidateOtpChallenge).create?).to be(true)

    %w[admin hr mps finance management].each do |role|
      policy = described_class.new(create(:user, role:), CandidateOtpChallenge)

      expect([policy.index?, policy.create?]).to eq([false, false]), role
    end
  end

  it 'denies a suspended developer and an unauthenticated actor' do
    suspended = create(:user, :suspended, role: 'developer')

    expect([described_class.new(suspended, CandidateOtpChallenge).index?,
            described_class.new(nil, CandidateOtpChallenge).index?]).to eq([false, false])
  end
end
