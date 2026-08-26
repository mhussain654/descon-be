# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateImportPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#create?' do
    it 'allows only staff with the active manage_candidates permission' do
      hr_user = create(:user, role: 'hr')
      admin = create(:user, role: 'admin')
      Permission.find_by!(code: 'manage_candidates').update!(active: false)

      expect(described_class.new(hr_user, :candidate_import).create?).to be(false)
      expect(described_class.new(admin, :candidate_import).create?).to be(false)
    end

    it 'denies inactive users and inactive roles' do
      actor = create(:user, role: 'hr')
      actor.update!(active: false)
      expect(described_class.new(actor, :candidate_import).create?).to be(false)

      actor = create(:user, role: 'hr')
      actor.staff_role.update!(active: false)
      expect(described_class.new(actor, :candidate_import).create?).to be(false)
    end

    it 'allows roles that currently have manage_candidates permission' do
      %w[admin hr].each do |role|
        expect(described_class.new(create(:user, role:), :candidate_import).create?).to be(true)
      end

      %w[mps finance management].each do |role|
        expect(described_class.new(create(:user, role:), :candidate_import).create?).to be(false)
      end
    end
  end
end
