# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::ReportPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index?' do
    it 'allows staff with an active view_reports permission (admin, mps, management)' do
      admin = create(:user, role: 'admin')
      mps = create(:user, role: 'mps')
      management = create(:user, role: 'management')
      denied_actors = %w[hr finance].map { |role| create(:user, role:) }

      expect(described_class.new(admin, :report).index?).to be(true)
      expect(described_class.new(mps, :report).index?).to be(true)
      expect(described_class.new(management, :report).index?).to be(true)
      expect(denied_actors).to all(satisfy { |actor| described_class.new(actor, :report).index? == false })
      expect(described_class.new(nil, :report).index?).to be(false)
    end

    it 'denies an inactive user' do
      inactive_mps = create(:user, role: 'mps', active: false)

      expect(described_class.new(inactive_mps, :report).index?).to be(false)
    end

    it 'denies a user when the view_reports permission record is inactive' do
      management = create(:user, role: 'management')
      Permission.find_by!(code: 'view_reports').update!(active: false)

      expect(described_class.new(management, :report).index?).to be(false)
    end
  end

  describe '#show?' do
    it 'delegates to #index?' do
      mps = create(:user, role: 'mps')
      hr = create(:user, role: 'hr')

      expect(described_class.new(mps, :report).show?).to be(true)
      expect(described_class.new(hr, :report).show?).to be(false)
    end
  end

  describe '#export?' do
    it 'delegates to #index?' do
      mps = create(:user, role: 'mps')
      hr = create(:user, role: 'hr')

      expect(described_class.new(mps, :report).export?).to be(true)
      expect(described_class.new(hr, :report).export?).to be(false)
    end
  end

  describe '::Scope' do
    it 'resolves the full report-type list for a permitted actor and none for a denied one' do
      management = create(:user, role: 'management')
      hr = create(:user, role: 'hr')
      report_types = %w[status_summary trend]

      expect(described_class::Scope.new(management, report_types).resolve).to eq(report_types)
      expect(described_class::Scope.new(hr, report_types).resolve).to eq([])
    end
  end
end
