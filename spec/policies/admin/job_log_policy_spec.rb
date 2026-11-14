# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::JobLogPolicy do
  before { ensure_staff_authorization_reference_data! }

  describe '#index?' do
    it 'allows only the developer (view_job_logs is developer-only)' do
      expect(described_class.new(create(:user, role: 'developer'), SolidQueue::Job).index?).to be(true)
    end

    it 'denies every other role, including admin' do
      %w[admin hr mps finance management].each do |role|
        expect(described_class.new(create(:user, role:), SolidQueue::Job).index?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, SolidQueue::Job).index?).to be(false)
    end
  end

  describe described_class::Scope do
    it 'returns no jobs to anyone without view_job_logs' do
      scope = described_class.new(create(:user, role: 'admin'), SolidQueue::Job.all).resolve

      expect(scope.to_sql).to eq(SolidQueue::Job.none.to_sql)
    end

    it 'returns every job to the developer' do
      scope = described_class.new(create(:user, role: 'developer'), SolidQueue::Job.all).resolve

      expect(scope.to_sql).to eq(SolidQueue::Job.all.to_sql)
    end
  end
end
