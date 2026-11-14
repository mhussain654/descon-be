# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::WorkflowCorrectionPolicy do
  before { ensure_staff_authorization_reference_data! }

  let(:candidate) { create(:candidate) }

  describe '#show? and #update?' do
    it 'allows only the developer (correct_workflow_details is developer-only)' do
      developer = create(:user, role: 'developer')

      expect(described_class.new(developer, candidate).show?).to be(true)
      expect(described_class.new(developer, candidate).update?).to be(true)
    end

    it 'denies every other role, including admin' do
      %w[admin hr mps finance management].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, candidate).show?).to be(false)
        expect(described_class.new(actor, candidate).update?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, candidate).update?).to be(false)
    end
  end
end
