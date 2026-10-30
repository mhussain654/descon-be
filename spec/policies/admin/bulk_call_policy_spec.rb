# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::BulkCallPolicy do
  before { ensure_staff_authorization_reference_data! }

  let(:admin) { create(:user, role: 'developer') }
  let(:finance) { create(:user, role: 'finance') }

  it 'lets admin and calling staff use bulk calling' do
    %w[admin hr mps].each do |role|
      policy = described_class.new(create(:user, role:), BulkCallBatch)

      expect([policy.index?, policy.show?, policy.create?, policy.candidates?]).to all(be(true))
    end
  end

  it 'lets the developer use bulk calling' do
    policy = described_class.new(admin, BulkCallBatch)

    expect([policy.index?, policy.show?, policy.create?, policy.candidates?]).to all(be(true))
  end

  it 'refuses staff without trigger_ai_calls' do
    policy = described_class.new(finance, BulkCallBatch)

    expect([policy.index?, policy.show?, policy.create?, policy.candidates?]).to all(be(false))
  end

  describe Admin::BulkCallPolicy::Scope do
    it 'resolves every batch for a permitted actor and none otherwise' do
      batch = create(:bulk_call_batch)

      expect(described_class.new(admin, BulkCallBatch).resolve).to contain_exactly(batch)
      expect(described_class.new(finance, BulkCallBatch).resolve).to be_empty
    end
  end
end
