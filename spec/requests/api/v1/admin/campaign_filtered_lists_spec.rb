# frozen_string_literal: true

require 'rails_helper'

# Phase 2 of campaigns: the remaining admin lists follow the working campaign.
RSpec.describe 'API V1 Admin lists narrowed to the working campaign', type: :request do
  include BulkCallHelpers

  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  let(:campaign) { create(:campaign) }
  let(:in_campaign) { create(:candidate_assignment, campaign:) }
  let(:in_test_campaign) { create(:candidate_assignment, campaign: create(:campaign, :test)) }
  let(:without_campaign) { create(:candidate_assignment) }

  def headers_for(selected_campaign)
    user = create(:user, role: 'developer', selected_campaign:)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def listed_ids(path, selected_campaign, params: {})
    get path, params:, headers: headers_for(selected_campaign)
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('data').pluck('id')
  end

  # Records of each assignment, then the ids listed for the campaign and for all campaigns.
  shared_examples 'a list following the working campaign' do |path, params = {}|
    it 'shows only the working campaign, and everything but the Test campaign for all campaigns' do
      record_in_campaign, record_in_test, record_without = [in_campaign, in_test_campaign, without_campaign].map do |a|
        create_record(a)
      end

      expect(listed_ids(path, campaign, params:)).to eq([record_in_campaign.public_id])
      expect(listed_ids(path, nil, params:)).to contain_exactly(record_in_campaign.public_id, record_without.public_id)
      expect(listed_ids(path, nil, params:)).not_to include(record_in_test.public_id)
    end
  end

  describe 'payments' do
    def create_record(assignment) = create(:payment, candidate_assignment: assignment)

    it_behaves_like 'a list following the working campaign', '/api/v1/admin/payments'
  end

  describe 'document reviews' do
    # A submission with one document waiting for review, so the queue lists it.
    def create_record(assignment)
      document = create(:candidate_document, candidate_assignment: assignment, status_code: 'under_verification')
      create(:candidate_document_submission, candidate_assignment: assignment).tap do |submission|
        create(:candidate_document_submission_item, candidate_document_submission: submission,
                                                    candidate_document: document)
      end
    end

    it_behaves_like 'a list following the working campaign', '/api/v1/admin/document_submissions'
  end

  describe 'communications' do
    def create_record(assignment) = create(:communication, candidate_assignment: assignment)

    it_behaves_like 'a list following the working campaign', '/api/v1/admin/communications'
  end

  describe 'AI calls' do
    def create_record(assignment)
      create(:candidate_ai_call, communication: create(:communication, candidate_assignment: assignment,
                                                                       channel_code: 'ai_voice_call'))
    end

    it_behaves_like 'a list following the working campaign', '/api/v1/admin/ai_calls',
                    { filter: { awaiting_review: 'false' } }
  end

  describe 'mobilization' do
    it 'shows only flights of the working campaign' do
      flight = create(:candidate_flight_detail, candidate_assignment: in_campaign)
      create(:candidate_flight_detail, candidate_assignment: without_campaign)

      expect(listed_ids('/api/v1/admin/mobilizations', campaign)).to eq([flight.public_id])
    end
  end

  describe 'bulk call candidates' do
    it 'lists and calls only candidates of the working campaign' do
      voice = create(:robocall_voice)
      candidate, assignment = candidate_at('verified')
      assignment.update!(campaign:)
      candidate_at('verified')

      get '/api/v1/admin/bulk_calls/candidates',
          params: { robocall_voice_id: voice.public_id, filter: { status: 'verified' }, called: 'all' },
          headers: headers_for(campaign)

      expect(response.parsed_body.fetch('data').pluck('id')).to eq([candidate.public_id])
    end
  end
end
