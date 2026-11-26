# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CampaignSelection do
  let(:campaign) { create(:campaign) }
  let(:test_campaign) { create(:campaign, :test) }
  # One candidate per case the filter must tell apart.
  let!(:candidates) do
    {
      in_campaign: create(:candidate_assignment, campaign:).candidate,
      in_test_campaign: create(:candidate_assignment, campaign: test_campaign).candidate,
      without_campaign: create(:candidate_assignment).candidate,
      without_assignment: create(:candidate)
    }
  end

  def selected(user) = described_class.new(user).apply(Candidate.all)

  it 'keeps only the working campaign when one is picked' do
    expect(selected(build(:user, selected_campaign: campaign))).to contain_exactly(candidates[:in_campaign])
  end

  it 'shows every candidate except the Test campaign for all campaigns' do
    expect(selected(build(:user)))
      .to include(candidates[:in_campaign], candidates[:without_campaign], candidates[:without_assignment])
    expect(selected(build(:user))).not_to include(candidates[:in_test_campaign])
  end

  it 'shows only the Test campaign when it is picked' do
    expect(selected(build(:user, selected_campaign: test_campaign))).to contain_exactly(candidates[:in_test_campaign])
  end

  it 'follows the current (latest) assignment' do
    create(:candidate_assignment, candidate: candidates[:in_campaign], created_at: 1.minute.from_now)

    expect(selected(build(:user, selected_campaign: campaign))).to be_empty
  end
end
