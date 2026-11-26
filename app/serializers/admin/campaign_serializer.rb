# frozen_string_literal: true

module Admin
  class CampaignSerializer
    # `candidate_count`: assignments in the campaign, when the caller counted them.
    def initialize(campaign, candidate_count: nil)
      @campaign = campaign
      @candidate_count = candidate_count
    end

    def as_json(*)
      {
        id: @campaign.public_id,
        code: @campaign.code,
        name: @campaign.name,
        kind: @campaign.kind,
        country: @campaign.country && { code: @campaign.country.code, name: @campaign.country.name_for },
        active: @campaign.active,
        created_at: @campaign.created_at.utc.iso8601
      }.tap { |json| json[:candidate_count] = @candidate_count unless @candidate_count.nil? }
    end
  end
end
