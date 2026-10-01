# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateAuthentication::Otp::RequestService do
  self.use_transactional_tests = false

  around do |example|
    AuthenticationEvent.delete_all
    AuditEvent.delete_all
    CandidateAssignment.delete_all
    CandidateOtpChallenge.delete_all
    CandidateRefreshToken.delete_all
    CandidateSession.delete_all
    RefreshToken.delete_all
    Session.delete_all
    CandidateConsent.delete_all
    Candidate.delete_all
    User.delete_all
    example.run
  ensure
    AuthenticationEvent.delete_all
    AuditEvent.delete_all
    CandidateAssignment.delete_all
    CandidateOtpChallenge.delete_all
    CandidateRefreshToken.delete_all
    CandidateSession.delete_all
    RefreshToken.delete_all
    Session.delete_all
    CandidateConsent.delete_all
    Candidate.delete_all
    User.delete_all
  end

  describe '.call' do
    it 'returns the same generic response shape for a valid, resolvable CNIC' do
      candidate = create(:candidate, mobile_number: '+923001234567')

      result = described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')

      expect(result).to eq(
        expires_in_seconds: CandidateOtpChallenge::EXPIRY_WINDOW.to_i,
        resend_after_seconds: CandidateOtpChallenge::RESEND_COOLDOWN.to_i
      )
    end

    # Client-approved, deliberate exception to the usual non-enumerating
    # response -- see CandidateCnicNotFoundError's own doc comment.
    it 'raises CandidateCnicNotFoundError for an unknown CNIC' do
      expect { described_class.call(cnic: '99999-9999999-9', ip_address: '10.0.0.1') }
        .to raise_error(CandidateCnicNotFoundError)
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
      rescue CandidateCnicNotFoundError
        nil
      end.not_to change(CandidateOtpChallenge, :count)
    end

    it 'never calls the SMS adapter for an unknown CNIC' do
      allow(Sms::SendMessage).to receive(:call)

      begin
        described_class.call(cnic: '99999-9999999-9', ip_address: '10.0.0.1')
      rescue CandidateCnicNotFoundError
        nil
      end

      expect(Sms::SendMessage).not_to have_received(:call)
    end

    it 'raises the same not-found error consistently on repeated attempts for an unknown CNIC' do
      2.times do
        expect { described_class.call(cnic: '99999-9999999-9', ip_address: '10.0.0.1') }
          .to raise_error(CandidateCnicNotFoundError)
      end
    end

    it "raises the not-found error in the request's current locale, with the submitted CNIC interpolated in" do
      I18n.with_locale(:ur) do
        expect { described_class.call(cnic: '99999-9999999-9', ip_address: '10.0.0.1') }
          .to raise_error(CandidateCnicNotFoundError) { |error|
                expect(error.message).to eq(
                  I18n.t('api.errors.candidate_cnic_not_found', cnic: '99999-9999999-9', locale: :ur)
                )
              }
      end
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

    it 'rejects mixed-content input that only becomes valid after stripping letters or symbols' do
      expect { described_class.call(cnic: 'abc42101xyz1234567-1', ip_address: '10.0.0.1') }
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

    it 'sends the OTP code and the real expiry minutes as the SMS template variables' do
      candidate = create(:candidate, mobile_number: '+923001234567')
      delivered = nil
      allow(Sms::SendMessage).to receive(:call) do |**kwargs|
        delivered = kwargs
        Sms::DeliveryResult.new(success: true, provider_reference: 'ref')
      end

      described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')

      expect(delivered.fetch(:variables)).to match(code: match(/\A\d{6}\z/), minutes: 5)
    end

    it 'uses the current request locale for a real candidate SMS body' do
      candidate = create(:candidate, preferred_locale: 'en')
      delivered_body = nil
      allow(Sms::SendMessage).to receive(:call) do |**kwargs|
        delivered_body = kwargs.fetch(:body)
        Sms::DeliveryResult.new(success: true, provider_reference: SecureRandom.uuid)
      end

      I18n.with_locale(:ur) do
        described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')
      end

      expect(delivered_body).to start_with('آپ کا ڈیسکون مین پاور تصدیقی کوڈ ')
      expect(delivered_body).not_to start_with('Your Descon Manpower verification code is ')
    end

    it 'serializes concurrent requests for the same CNIC so only one challenge is created during cooldown' do
      candidate = create(:candidate)
      results = Queue.new
      allow(Candidate).to receive(:find_by).and_wrap_original do |method, *args|
        sleep 0.05
        method.call(*args)
      end
      allow(Sms::SendMessage).to receive(:call).and_return(
        Sms::DeliveryResult.new(success: true, provider_reference: SecureRandom.uuid)
      )

      worker = lambda do
        ActiveRecord::Base.connection_pool.with_connection do
          results << described_class.call(cnic: candidate.cnic, ip_address: '10.0.0.1')
        end
      end

      threads = Array.new(2) { Thread.new(&worker) }
      threads.each(&:join)

      expect(Array.new(2) { results.pop }).to all include(
        expires_in_seconds: CandidateOtpChallenge::EXPIRY_WINDOW.to_i,
        resend_after_seconds: CandidateOtpChallenge::RESEND_COOLDOWN.to_i
      )
      expect(CandidateOtpChallenge.where(cnic: candidate.cnic).count).to eq(1)
      expect(Sms::SendMessage).to have_received(:call).once
    end
  end
end
