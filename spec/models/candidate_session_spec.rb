# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateSession, type: :model do
  subject { create(:candidate_session) }

  it { is_expected.to belong_to(:candidate) }
  it { is_expected.to have_many(:candidate_refresh_tokens).dependent(:destroy) }

  describe 'identifier assignment' do
    it 'assigns public_id and jti on create when not supplied' do
      session = described_class.new(candidate: create(:candidate))
      session.save!
      expect(session.public_id).to be_present
      expect(session.jti).to be_present
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:public_id) }
    it { is_expected.to validate_uniqueness_of(:public_id) }
    it { is_expected.to validate_presence_of(:jti) }
    it { is_expected.to validate_uniqueness_of(:jti) }
  end

  describe '#revoke!' do
    it 'sets revoked_at and revokes every active refresh token in one transaction' do
      session = create(:candidate_session)
      active_token = create(:candidate_refresh_token, candidate_session: session)

      session.revoke!

      expect(session.reload).to be_revoked
      expect(active_token.reload.revoked_at).to be_present
    end

    it 'does not touch a refresh token that was already revoked or rotated' do
      session = create(:candidate_session)
      rotated_token = create(:candidate_refresh_token, candidate_session: session, rotated_at: 1.day.ago)

      session.revoke!

      expect(rotated_token.reload.revoked_at).to be_nil
    end
  end

  describe '#touch_last_seen!' do
    it 'updates last_seen_at when never set' do
      session = create(:candidate_session, last_seen_at: nil)
      session.touch_last_seen!
      expect(session.reload.last_seen_at).to be_present
    end

    it 'does not update last_seen_at again within 5 minutes' do
      session = create(:candidate_session, last_seen_at: 1.minute.ago)
      original = session.last_seen_at

      session.touch_last_seen!

      expect(session.reload.last_seen_at).to be_within(1).of(original)
    end
  end

  describe '.active' do
    it 'excludes revoked sessions' do
      active = create(:candidate_session)
      revoked = create(:candidate_session, revoked_at: Time.current)

      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(revoked)
    end
  end
end
