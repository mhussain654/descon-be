# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateAuthentication::Otp::VerifyService do
  self.use_transactional_tests = false

  around do |example|
    CandidateOtpChallenge.delete_all
    CandidateRefreshToken.delete_all
    CandidateSession.delete_all
    Candidate.delete_all
    User.delete_all
    example.run
  ensure
    CandidateOtpChallenge.delete_all
    CandidateRefreshToken.delete_all
    CandidateSession.delete_all
    Candidate.delete_all
    User.delete_all
  end

  def call(cnic:, code:)
    described_class.call(cnic:, code:, user_agent: 'RSpec', ip_address: '10.0.0.1')
  end

  describe '.call' do
    context 'with a valid, unexpired challenge and the correct code' do
      it 'creates a candidate session and issues an access and refresh token' do
        candidate = create(:candidate)
        result = CandidateOtpChallenge.generate_for(candidate:)

        outcome = call(cnic: candidate.cnic, code: result.fetch(:code))

        expect(outcome.fetch(:access_token)).to be_present
        expect(outcome.fetch(:refresh_token)).to be_present
        expect(outcome.fetch(:candidate)).to eq(candidate)
        expect(outcome.fetch(:candidate_session)).to be_persisted
      end

      it 'consumes the challenge so it cannot be replayed' do
        candidate = create(:candidate)
        result = CandidateOtpChallenge.generate_for(candidate:)

        call(cnic: candidate.cnic, code: result.fetch(:code))

        expect(result.fetch(:challenge).reload).to be_consumed
      end

      it 'accepts a CNIC submitted without dashes' do
        candidate = create(:candidate, cnic: '42101-1234567-1')
        result = CandidateOtpChallenge.generate_for(candidate:)

        expect { call(cnic: '4210112345671', code: result.fetch(:code)) }.not_to raise_error
      end

      it 'issues a token whose audience is candidate-specific, distinct from staff tokens' do
        candidate = create(:candidate)
        result = CandidateOtpChallenge.generate_for(candidate:)

        outcome = call(cnic: candidate.cnic, code: result.fetch(:code))
        decoded = CandidateAuthentication::TokenDecoder.call(token: outcome.fetch(:access_token))

        expect(decoded['aud']).to eq(ENV.fetch('CANDIDATE_JWT_AUDIENCE', 'candidate_api_clients'))
        expect { Authentication::TokenDecoder.call(token: outcome.fetch(:access_token)) }
          .to raise_error(JWT::InvalidAudError)
      end

      it 'allows only one concurrent success for the same OTP' do
        candidate = create(:candidate)
        result = CandidateOtpChallenge.generate_for(candidate:)
        outcomes = Queue.new

        worker = lambda do
          ActiveRecord::Base.connection_pool.with_connection do
            payload = call(cnic: candidate.cnic, code: result.fetch(:code))
            outcomes << [:success, payload.fetch(:candidate_session).id]
          rescue OtpInvalidError => e
            outcomes << [:error, e.code]
          end
        end

        threads = Array.new(2) { Thread.new(&worker) }
        threads.each(&:join)
        results = Array.new(2) { outcomes.pop }

        expect(results.count { |type, _| type == :success }).to eq(1)
        expect(results.count { |type, code| type == :error && code == 'otp_invalid' }).to eq(1)
        expect(CandidateSession.where(candidate:).count).to eq(1)
        expect(result.fetch(:challenge).reload).to be_consumed
      end

      it 'rolls back challenge consumption when session or token persistence fails' do
        candidate = create(:candidate)
        result = CandidateOtpChallenge.generate_for(candidate:)
        allow(CandidateAuthentication::RefreshTokenIssuer).to receive(:call).and_raise(StandardError, 'boom')

        expect { call(cnic: candidate.cnic, code: result.fetch(:code)) }.to raise_error(StandardError, 'boom')

        expect(result.fetch(:challenge).reload).not_to be_consumed
        expect(CandidateSession.where(candidate:).count).to eq(0)
        expect(CandidateRefreshToken.count).to eq(0)
      end
    end

    context 'when the CNIC does not resolve to any candidate' do
      it 'raises the generic OtpInvalidError' do
        expect { call(cnic: '99999-9999999-9', code: '123456') }.to raise_error(OtpInvalidError)
      end
    end

    context 'when the CNIC is known but no challenge was ever requested' do
      it 'raises the generic OtpInvalidError, identical to an unknown CNIC' do
        candidate = create(:candidate)
        expect { call(cnic: candidate.cnic, code: '123456') }.to raise_error(OtpInvalidError)
      end
    end

    context 'when the CNIC is unknown but a decoy challenge was requested for it' do
      it 'raises OtpExpiredError once the decoy has expired, identical to a real candidate' do
        create(:candidate_otp_challenge, :decoy, :expired, cnic: '99999-9999999-9', code_digest: BCrypt::Password.create('123456'))

        expect { call(cnic: '99999-9999999-9', code: '123456') }.to raise_error(OtpExpiredError)
      end

      it 'raises OtpMaxAttemptsError once the decoy is locked, identical to a real candidate' do
        create(:candidate_otp_challenge, :decoy, :locked, cnic: '99999-9999999-9', code_digest: BCrypt::Password.create('123456'))

        expect { call(cnic: '99999-9999999-9', code: '123456') }.to raise_error(OtpMaxAttemptsError)
      end

      it 'raises OtpInvalidError, never succeeds, even when the decoy code happens to be guessed correctly' do
        decoy = create(:candidate_otp_challenge, :decoy, cnic: '99999-9999999-9', code_digest: BCrypt::Password.create('654321'))

        expect { call(cnic: '99999-9999999-9', code: '654321') }.to raise_error(OtpInvalidError)
        expect(decoy.reload).not_to be_consumed
      end

      it 'increments the decoy attempt counter on a wrong guess, just like a real challenge' do
        decoy = create(:candidate_otp_challenge, :decoy, cnic: '99999-9999999-9', code_digest: BCrypt::Password.create('654321'))

        expect { call(cnic: '99999-9999999-9', code: '000000') }.to raise_error(OtpInvalidError)
        expect(decoy.reload.attempts).to eq(1)
      end
    end

    context 'with an incorrect code against a real, active challenge' do
      it 'raises OtpInvalidError and increments the attempt counter' do
        candidate = create(:candidate)
        result = CandidateOtpChallenge.generate_for(candidate:)
        wrong_code = result.fetch(:code) == '000000' ? '111111' : '000000'

        expect { call(cnic: candidate.cnic, code: wrong_code) }.to raise_error(OtpInvalidError)
        expect(result.fetch(:challenge).reload.attempts).to eq(1)
      end
    end

    context 'when attempts reach MAX_ATTEMPTS' do
      it 'raises OtpMaxAttemptsError on the attempt that reaches the limit' do
        candidate = create(:candidate)
        challenge = create(:candidate_otp_challenge, candidate:,
                                                     attempts: CandidateOtpChallenge::MAX_ATTEMPTS - 1,
                                                     code_digest: BCrypt::Password.create('123456'))

        expect { call(cnic: candidate.cnic, code: '000000') }.to raise_error(OtpMaxAttemptsError)
        expect(challenge.reload).to be_locked
      end

      it 'raises OtpMaxAttemptsError even for the correct code once locked' do
        candidate = create(:candidate)
        create(:candidate_otp_challenge, :locked, candidate:, code_digest: BCrypt::Password.create('123456'))

        expect { call(cnic: candidate.cnic, code: '123456') }.to raise_error(OtpMaxAttemptsError)
      end
    end

    context 'with an expired challenge' do
      it 'raises OtpExpiredError, distinct from an invalid code' do
        candidate = create(:candidate)
        create(:candidate_otp_challenge, :expired, candidate:, code_digest: BCrypt::Password.create('123456'))

        expect { call(cnic: candidate.cnic, code: '123456') }.to raise_error(OtpExpiredError)
      end
    end

    context 'when replaying an already-consumed challenge' do
      it 'raises the generic OtpInvalidError, not a distinguishable "already used" error' do
        candidate = create(:candidate)
        result = CandidateOtpChallenge.generate_for(candidate:)
        call(cnic: candidate.cnic, code: result.fetch(:code))

        expect { call(cnic: candidate.cnic, code: result.fetch(:code)) }.to raise_error(OtpInvalidError)
      end
    end

    context 'with malformed input' do
      it 'raises a field-addressable validation error for a malformed CNIC' do
        expect { call(cnic: 'not-a-cnic', code: '123456') }
          .to raise_error(ValidationError) { |error| expect(error.field).to eq('cnic') }
      end

      it 'raises a field-addressable validation error for a non-numeric or wrong-length code' do
        candidate = create(:candidate)
        expect { call(cnic: candidate.cnic, code: 'abcdef') }
          .to raise_error(ValidationError) { |error| expect(error.field).to eq('otp') }
      end
    end
  end
end
