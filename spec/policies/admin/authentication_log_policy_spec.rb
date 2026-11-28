# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::AuthenticationLogPolicy do
  before { ensure_staff_authorization_reference_data! }

  describe '#index?' do
    it 'allows only the developer (view_authentication_logs is developer-only)' do
      expect(described_class.new(create(:user, role: 'developer'), Candidate).index?).to be(true)
    end

    it 'denies every other role, including admin' do
      %w[admin hr mps finance management].each do |role|
        expect(described_class.new(create(:user, role:), Candidate).index?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, Candidate).index?).to be(false)
    end
  end

  describe '#show?' do
    it 'follows index?' do
      expect(described_class.new(create(:user, role: 'developer'), Candidate).show?).to be(true)
      expect(described_class.new(create(:user, role: 'admin'), Candidate).show?).to be(false)
    end
  end

  describe described_class::Scope do
    it 'returns no rows to anyone without view_authentication_logs' do
      scope = described_class.new(create(:user, role: 'admin'), Candidate.all).resolve

      expect(scope.to_sql).to eq(Candidate.none.to_sql)
    end

    it 'returns every row to the developer' do
      scope = described_class.new(create(:user, role: 'developer'), Candidate.all).resolve

      expect(scope.to_sql).to eq(Candidate.all.to_sql)
    end
  end
end
