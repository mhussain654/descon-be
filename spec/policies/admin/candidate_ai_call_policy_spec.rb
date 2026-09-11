# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateAiCallPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index? and #create?' do
    it 'allows staff with trigger_ai_calls (admin, hr, mps)' do
      %w[admin hr mps].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, CandidateAiCall).index?).to be(true)
        expect(described_class.new(actor, CandidateAiCall).create?).to be(true)
      end
    end

    it 'denies staff without trigger_ai_calls' do
      %w[finance management].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, CandidateAiCall).index?).to be(false)
        expect(described_class.new(actor, CandidateAiCall).create?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, CandidateAiCall).index?).to be(false)
    end

    it 'denies an inactive user' do
      inactive_admin = create(:user, role: 'hr', active: false)

      expect(described_class.new(inactive_admin, CandidateAiCall).index?).to be(false)
    end
  end

  describe '::Scope' do
    it 'resolves the full scope for a permitted actor and none for a denied one' do
      admin = create(:user, role: 'admin')
      finance = create(:user, role: 'finance')
      create(:candidate_ai_call)

      expect(described_class::Scope.new(admin, CandidateAiCall.all).resolve.count).to eq(1)
      expect(described_class::Scope.new(finance, CandidateAiCall.all).resolve.count).to eq(0)
    end
  end
end
