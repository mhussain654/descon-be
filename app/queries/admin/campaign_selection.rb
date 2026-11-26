# frozen_string_literal: true

module Admin
  # The staff member's working campaign (`users.selected_campaign_id`), applied to
  # every candidate list, dashboard and report:
  # - a campaign picked: only candidates whose current assignment is in it;
  # - all campaigns (nothing picked): every candidate except the Test campaign's.
  #
  # Narrows by `candidates.id IN (subquery)` so it composes with queries that
  # do their own current-assignment join (see Reports::DashboardFilterResolution).
  class CampaignSelection
    attr_reader :campaign

    def initialize(user)
      @campaign = user&.selected_campaign
    end

    def all_campaigns? = campaign.nil?

    def apply(scope)
      return scope.where.not(id: candidate_ids_in(test_campaign_ids)) if all_campaigns?

      scope.where(id: candidate_ids_in(campaign.id))
    end

    # The same rule for records that belong to an assignment (payments,
    # document submissions, communications, AI calls): kept or dropped by
    # their candidate. Under all campaigns a record without an assignment stays.
    def apply_to_assignment_records(scope, column: :candidate_assignment_id)
      candidate_ids = candidate_ids_in(all_campaigns? ? test_campaign_ids : campaign.id)
      matching = scope.model.where(column => ::CandidateAssignment.where(candidate_id: candidate_ids).select(:id))
      all_campaigns? ? scope.where.not(id: matching.select(:id)) : scope.where(id: matching.select(:id))
    end

    # For records that name a candidate campaign directly (imports): the working
    # campaign's, or under all campaigns everything but the Test campaign's.
    def apply_to_campaign_records(scope, column: :campaign_id)
      return scope.where(column => campaign.id) unless all_campaigns?

      scope.where(column => nil).or(scope.where.not(column => test_campaign_ids))
    end

    private

    # Candidates whose current (latest) assignment is in the given campaign(es).
    def candidate_ids_in(campaign_ids)
      Reports::CurrentAssignmentJoin.call(scope: Candidate.unscoped)
                                    .where(current_assignments: { campaign_id: campaign_ids })
                                    .select('candidates.id')
    end

    def test_campaign_ids = Campaign.where(kind: Campaign::TEST_KIND).select(:id)
  end
end
