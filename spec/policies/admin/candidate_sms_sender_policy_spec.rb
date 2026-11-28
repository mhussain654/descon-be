# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateSmsSenderPolicy do
  before { ensure_staff_authorization_reference_data! }

  describe '#update?' do
    it 'allows every staff role' do
      %w[developer admin hr mps finance management].each do |role|
        expect(described_class.new(create(:user, role:), Candidate).update?).to be(true), role
      end
    end

    it 'denies an inactive staff member and an unauthenticated actor' do
      inactive = create(:user, :suspended)

      expect([described_class.new(inactive, Candidate).update?, described_class.new(nil, Candidate).update?])
        .to eq([false, false])
    end
  end
end
