# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaign, type: :model do
  it 'codes a campaign by date and country, adding -2, -3 when taken' do
    country = create(:country, code: 'qatar_campaign_test')
    date = Date.new(2026, 11, 26)

    first = described_class.next_code(date:, country:)
    create(:campaign, code: first, country:)
    second = described_class.next_code(date:, country:)
    create(:campaign, code: second, country:)

    expect([first, second, described_class.next_code(date:, country:)])
      .to eq(%w[2026-11-26-QATAR_CAMPAIGN_TEST 2026-11-26-QATAR_CAMPAIGN_TEST-2 2026-11-26-QATAR_CAMPAIGN_TEST-3])
  end

  it 'needs a country for a regular campaign but not for the Test campaign' do
    expect(build(:campaign, country: nil)).not_to be_valid
    expect(build(:campaign, :test)).to be_valid
  end

  it 'finds the single Test campaign' do
    test_campaign = create(:campaign, :test)

    expect(described_class.test_campaign).to eq(test_campaign)
    expect(test_campaign).to be_test
  end
end
