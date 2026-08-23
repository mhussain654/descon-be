# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateAuthentication::Otp::RequestService do
  describe '.call' do
    it 'returns the same generic response shape for a valid, resolvable CNIC' do
      candidate = create(:candidate, mobile_number: '+923001234567')

      result = described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')

      expect(result).to eq(
        expires_in_seconds: CandidateOtpChallenge::EXPIRY_WINDOW.to_i,
        resend_after_seconds: CandidateOtpChallenge::RESEND_COOLDOWN.to_i
      )
    end

    it 'returns the identical response shape for an unknown CNIC' do
      result = described_class.call(cnic: '99999-9999999-9', ip_address: '10.0.0.1')

      expect(result).to eq(
        expires_in_seconds: CandidateOtpChallenge::EXPIRY_WINDOW.to_i,
        resend_after_seconds: CandidateOtpChallenge::RESEND_COOLDOWN.to_i
      )
    end

    it 'returns the identical response shape when the candidate mobile is undeliverable' do
      candidate = create(:candidate, mobile_number: '+923000000000')

      result = described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')

      expect(result).to eq(
        expires_in_seconds: CandidateOtpChallenge::EXPIRY_WINDOW.to_i,
        resend_after_seconds: CandidateOtpChallenge::RESEND_COOLDOWN.to_i
      )
    end

    it 'creates a challenge only for a candidate that actually resolves' do
      candidate = create(:candidate)

      expect do
        described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')
      end.to change(CandidateOtpChallenge, :count).by(1)
    end

    it 'does not create any challenge for an unknown CNIC' do
      expect do
        described_class.call(cnic: '99999-9999999-9', ip_address: '10.0.0.1')
      end.not_to change(CandidateOtpChallenge, :count)
    end

    it 'accepts a CNIC without dashes and normalizes it before lookup' do
      candidate = create(:candidate, cnic: '42101-1234567-1')

      expect do
        described_class.call(cnic: '4210112345671', ip_address: '10.0.0.1')
      end.to change(CandidateOtpChallenge, :count).by(1)

      expect(candidate.candidate_otp_challenges.count).to eq(1)
    end

    it 'raises a field-addressable validation error for a malformed CNIC' do
      expect { described_class.call(cnic: 'not-a-cnic', ip_address: '10.0.0.1') }
        .to raise_error(ValidationError) { |error| expect(error.field).to eq('cnic') }
    end

    it 'does not send another SMS or create a new challenge within the resend cooldown' do
      candidate = create(:candidate)
      described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')

      expect do
        described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')
      end.not_to change(CandidateOtpChallenge, :count)
    end

    it 'creates a fresh challenge once the resend cooldown has elapsed' do
      candidate = create(:candidate)
      described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')

      travel_to((CandidateOtpChallenge::RESEND_COOLDOWN + 1.second).from_now) do
        expect do
          described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')
        end.to change(CandidateOtpChallenge, :count).by(1)
      end
    end

    it 'invalidates the prior code once a fresh one is requested' do
      candidate = create(:candidate)
      described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')
      first_challenge = candidate.candidate_otp_challenges.order(:created_at).first

      travel_to((CandidateOtpChallenge::RESEND_COOLDOWN + 1.second).from_now) do
        described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')
      end

      latest = candidate.candidate_otp_challenges.order(created_at: :desc).first
      expect(latest).not_to eq(first_challenge)
    end

    it 'does not raise when the SMS provider itself raises' do
      candidate = create(:candidate)
      allow(Sms::SendMessage).to receive(:call).and_raise(StandardError, 'provider down')

      expect { described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1') }.not_to raise_error
    end
  end
end
