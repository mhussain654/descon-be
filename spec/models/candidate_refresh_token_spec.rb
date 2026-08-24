# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateRefreshToken, type: :model do
  subject { create(:candidate_refresh_token) }

  it { is_expected.to belong_to(:candidate_session) }
  it { is_expected.to validate_presence_of(:token_digest) }
  it { is_expected.to validate_uniqueness_of(:token_digest) }
  it { is_expected.to validate_presence_of(:expires_at) }

  describe '#active?' do
    it 'is true for a fresh, unrevoked, unrotated token' do
      expect(create(:candidate_refresh_token)).to be_active
    end

    it 'is false once revoked' do
      expect(create(:candidate_refresh_token, revoked_at: Time.current)).not_to be_active
    end

    it 'is false once rotated' do
      expect(create(:candidate_refresh_token, rotated_at: Time.current)).not_to be_active
    end

    it 'is false once expired' do
      expect(create(:candidate_refresh_token, expires_at: 1.minute.ago)).not_to be_active
    end
  end

  describe '.active scope' do
    it 'returns only tokens that are unrevoked, unrotated and unexpired' do
      active = create(:candidate_refresh_token)
      revoked = create(:candidate_refresh_token, revoked_at: Time.current)
      rotated = create(:candidate_refresh_token, rotated_at: Time.current)
      expired = create(:candidate_refresh_token, expires_at: 1.minute.ago)

      expect(described_class.active).to contain_exactly(active)
      expect(described_class.active).not_to include(revoked, rotated, expired)
    end
  end

  describe '#replacement' do
    it 'links to the token that replaced it' do
      original = create(:candidate_refresh_token)
      replacement = create(:candidate_refresh_token, candidate_session: original.candidate_session)
      original.update!(replaced_by_id: replacement.id)

      expect(original.reload.replacement).to eq(replacement)
    end
  end
end
