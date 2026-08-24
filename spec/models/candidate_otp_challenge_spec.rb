# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateOtpChallenge, type: :model do
  describe '.generate_for' do
    it 'creates a persisted challenge and returns the raw code alongside it' do
      candidate = create(:candidate)

      result = described_class.generate_for(candidate:, requested_ip: '10.0.0.1')

      expect(result.fetch(:challenge)).to be_persisted
      expect(result.fetch(:challenge).candidate).to eq(candidate)
      expect(result.fetch(:challenge).requested_ip).to eq('10.0.0.1')
      expect(result.fetch(:code)).to match(/\A\d{6}\z/)
    end

    it 'defaults cnic from the candidate when cnic is not given explicitly' do
      candidate = create(:candidate)
      result = described_class.generate_for(candidate:)
      expect(result.fetch(:challenge).cnic).to eq(candidate.cnic)
    end

    it 'creates a decoy challenge with no candidate for a CNIC that does not resolve to one' do
      result = described_class.generate_for(cnic: '99999-9999999-9')

      expect(result.fetch(:challenge)).to be_persisted
      expect(result.fetch(:challenge).candidate).to be_nil
      expect(result.fetch(:challenge).cnic).to eq('99999-9999999-9')
      expect(result.fetch(:code)).to match(/\A\d{6}\z/)
    end

    it 'stores the code only as a bcrypt digest, never in plaintext' do
      result = described_class.generate_for(candidate: create(:candidate))

      expect(result.fetch(:challenge).code_digest).not_to eq(result.fetch(:code))
      expect(result.fetch(:challenge).code_digest).to start_with('$2a$').or start_with('$2b$')
    end

    it 'sets expiry from the configured EXPIRY_WINDOW' do
      freeze_time do
        result = described_class.generate_for(candidate: create(:candidate))
        expect(result.fetch(:challenge).expires_at).to eq(described_class::EXPIRY_WINDOW.from_now)
      end
    end
  end

  describe '#match?' do
    it 'returns true for the code it was generated with' do
      result = described_class.generate_for(candidate: create(:candidate))
      expect(result.fetch(:challenge).match?(result.fetch(:code))).to be(true)
    end

    it 'returns false for any other code' do
      challenge = create(:candidate_otp_challenge, code_digest: BCrypt::Password.create('123456'))
      expect(challenge.match?('000000')).to be(false)
    end
  end

  describe '#usable?' do
    it 'is true for a fresh challenge' do
      expect(create(:candidate_otp_challenge)).to be_usable
    end

    it 'is false once expired' do
      expect(create(:candidate_otp_challenge, :expired)).not_to be_usable
    end

    it 'is false once consumed' do
      expect(create(:candidate_otp_challenge, :consumed)).not_to be_usable
    end

    it 'is false once locked' do
      expect(create(:candidate_otp_challenge, :locked)).not_to be_usable
    end
  end

  describe '#register_failed_attempt!' do
    it 'increments attempts by one' do
      challenge = create(:candidate_otp_challenge, attempts: 2)
      challenge.register_failed_attempt!
      expect(challenge.reload.attempts).to eq(3)
    end

    it 'becomes locked once attempts reach MAX_ATTEMPTS' do
      challenge = create(:candidate_otp_challenge, attempts: described_class::MAX_ATTEMPTS - 1)
      challenge.register_failed_attempt!
      expect(challenge.reload).to be_locked
    end
  end

  describe '#consume!' do
    it 'sets consumed_at' do
      challenge = create(:candidate_otp_challenge)
      challenge.consume!
      expect(challenge.reload.consumed_at).to be_present
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:cnic) }
    it { is_expected.to validate_presence_of(:code_digest) }
    it { is_expected.to validate_presence_of(:expires_at) }
    it { is_expected.to belong_to(:candidate).optional }
  end
end
