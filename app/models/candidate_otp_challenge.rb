# frozen_string_literal: true

# A candidate's most recent challenge is always the only one that can
# succeed at verify (see CandidateAuthentication::Otp::VerifyService) --
# requesting a fresh code naturally invalidates any earlier one without
# needing to explicitly mark it superseded.
#
# The code is hashed with bcrypt, not a plain digest like RefreshToken's
# SecureRandom.hex(48) tokens: a 6-digit OTP has only 1,000,000 possible
# values, so a fast, unsalted digest (e.g. SHA-256) would let anyone with
# read access to this table precompute every possible hash in seconds.
# Bcrypt's per-record salt and deliberate slowness make that infeasible.
class CandidateOtpChallenge < ApplicationRecord
  CODE_LENGTH = ENV.fetch('OTP_CODE_LENGTH', 6).to_i
  EXPIRY_WINDOW = ENV.fetch('OTP_EXPIRY_SECONDS', 300).to_i.seconds
  RESEND_COOLDOWN = ENV.fetch('OTP_RESEND_COOLDOWN_SECONDS', 60).to_i.seconds
  MAX_ATTEMPTS = ENV.fetch('OTP_MAX_ATTEMPTS', 5).to_i

  belongs_to :candidate

  validates :code_digest, presence: true
  validates :expires_at, presence: true
  validates :attempts, numericality: { greater_than_or_equal_to: 0 }

  # Generates a new challenge and returns the raw code alongside it. The raw
  # code exists only in this return value and the caller's local scope --
  # it is never persisted or logged (AGENTS.md: "OTP values must be random,
  # short-lived, single-use and stored as a digest" / ticket: "OTP is never
  # returned in any API response or log").
  def self.generate_for(candidate:, requested_ip: nil)
    code = SecureRandom.random_number(10**CODE_LENGTH).to_s.rjust(CODE_LENGTH, '0')
    challenge = candidate.candidate_otp_challenges.create!(
      code_digest: BCrypt::Password.create(code),
      expires_at: EXPIRY_WINDOW.from_now,
      requested_ip:
    )
    { challenge:, code: }
  end

  def match?(code)
    BCrypt::Password.new(code_digest) == code.to_s
  end

  def expired?
    expires_at.past?
  end

  def consumed?
    consumed_at.present?
  end

  def locked?
    attempts >= MAX_ATTEMPTS
  end

  def usable?
    !expired? && !consumed? && !locked?
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  def register_failed_attempt!
    increment!(:attempts) # rubocop:disable Rails/SkipsModelValidations -- atomic counter increment, not a full save
  end
end
