# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateSmsMessagePolicy do
  before { ensure_staff_authorization_reference_data! }

  describe '#index? and #create?' do
    it 'allows the roles that can contact a candidate' do
      %w[developer admin hr mps].each do |role|
        policy = described_class.new(create(:user, role:), CandidateSmsDelivery)

        expect([policy.index?, policy.create?]).to eq([true, true]), role
      end
    end

    it 'denies finance and management' do
      %w[finance management].each do |role|
        policy = described_class.new(create(:user, role:), CandidateSmsDelivery)

        expect([policy.index?, policy.create?]).to eq([false, false]), role
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, CandidateSmsDelivery).create?).to be(false)
    end
  end
end
