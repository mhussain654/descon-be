# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateOtpChallenge, '#history_status' do
  let(:challenge) { described_class.generate_for(candidate: create(:candidate)).fetch(:challenge) }

  it 'reads pending, then used, locked or expired' do
    expect(challenge.history_status).to eq('pending')
    expect(challenge.dup.tap { |copy| copy.consumed_at = Time.current }.history_status).to eq('used')
    expect(challenge.dup.tap { |copy| copy.attempts = described_class::MAX_ATTEMPTS }.history_status).to eq('locked')
    expect(challenge.dup.tap { |copy| copy.expires_at = 1.second.ago }.history_status).to eq('expired')
  end
end
