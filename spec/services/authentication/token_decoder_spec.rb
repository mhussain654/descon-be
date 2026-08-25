# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Authentication::TokenDecoder do
  it 'rejects a candidate token in the staff decoder' do
    candidate = create(:candidate)
    candidate_session = create(:candidate_session, candidate:)
    token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)

    expect { described_class.call(token:) }.to raise_error(JWT::InvalidAudError)
  end

  it 'rejects a staff token in the candidate decoder' do
    user = create(:user)
    session = create(:session, user:)
    token = Authentication::TokenIssuer.call(user:, session:)

    expect { CandidateAuthentication::TokenDecoder.call(token:) }.to raise_error(JWT::InvalidAudError)
  end
end
