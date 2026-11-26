# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lists candidate campaigns (for the working-campaign picker and the import and
      # New candidate forms) and creates new ones.
      class CampaignsController < ProtectedStaffController
        include IdempotentRequestHandling

        # Active campaigns, newest first, with how many candidates each holds.
        # `include_retired=true` adds retired ones.
        def index
          authorize ::Campaign, :index?, policy_class: ::Admin::CampaignPolicy

          campaigns = listed_campaigns
          counts = ::CandidateAssignment.where(campaign_id: campaigns.select(:id)).group(:campaign_id).count
          render_success(data: campaigns.map { |campaign| serialized(campaign, counts.fetch(campaign.id, 0)) })
        end

        def create
          authorize ::Campaign, :create?, policy_class: ::Admin::CampaignPolicy

          render_idempotent_response(scope: 'admin.campaigns.create', subject: current_user,
                                     fingerprint: create_params.to_h.to_json) do
            campaign = ::Admin::Campaigns::CreateService.call(actor: current_user,
                                                              **create_params.to_h.symbolize_keys)
            success_payload(data: serialized(campaign, 0), status: :created)
          end
        end

        private

        # The Test campaign first, then the newest.
        def listed_campaigns
          campaigns = policy_scope(::Campaign, policy_scope_class: ::Admin::CampaignPolicy::Scope)
          campaigns = campaigns.active unless ActiveModel::Type::Boolean.new.cast(params[:include_retired])
          campaigns.includes(:country).order(kind: :desc, created_at: :desc)
        end

        def create_params
          params.expect(campaign: %i[country_code name start_date])
        end

        def serialized(campaign, count) = ::Admin::CampaignSerializer.new(campaign, candidate_count: count).as_json
      end
    end
  end
end
