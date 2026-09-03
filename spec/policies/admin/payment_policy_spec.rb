# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::PaymentPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  let(:payment) { create(:payment) }

  it 'allows index/show for view_payments or manage_payments roles, and create_correction only for manage_payments' do
    admin = create(:user, role: 'admin')
    finance = create(:user, role: 'finance')
    management = create(:user, role: 'management')
    hr = create(:user, role: 'hr')

    expect(described_class.new(admin, payment).show?).to be(true)
    expect(described_class.new(admin, payment).create_correction?).to be(true)

    expect(described_class.new(finance, payment).show?).to be(true)
    expect(described_class.new(finance, payment).create_correction?).to be(true)

    expect(described_class.new(management, payment).show?).to be(true)
    expect(described_class.new(management, payment).create_correction?).to be(false)

    expect(described_class.new(hr, payment).show?).to be(false)
    expect(described_class.new(hr, payment).create_correction?).to be(false)
  end

  it 'index? mirrors show?' do
    finance = create(:user, role: 'finance')

    expect(described_class.new(finance, Payment).index?).to eq(described_class.new(finance, Payment).show?)
  end

  describe 'Scope' do
    it 'returns everything for a staff member with view_payments or manage_payments, and nothing otherwise' do
      create(:payment)
      finance = create(:user, role: 'finance')
      hr = create(:user, role: 'hr')

      expect(described_class::Scope.new(finance, Payment).resolve.count).to eq(1)
      expect(described_class::Scope.new(hr, Payment).resolve.count).to eq(0)
    end
  end
end
