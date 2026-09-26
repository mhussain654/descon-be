# frozen_string_literal: true

module AiCalls
  # Compares (#check) and pushes (#sync!) the repo-committed canonical
  # baseline agent configuration (AiCalls::AgentConfigs::Baseline) against
  # what's currently published on ElevenLabs, so the permanent
  # guardrail-bearing agent prompt never silently drifts from the reviewed
  # repo version. Backs the two `ai_calls:agent_config:*` rake tasks.
  #
  # #check is read-only and always safe to run. #sync! writes, and refuses
  # to run against production unless explicitly confirmed (mirrors
  # Backups::RestoreDatabaseBackupService#refuse_in_production!) -- and,
  # regardless of confirmation, always refuses to push a still-placeholder
  # baseline into production (AiCalls::AgentConfigs::Baseline#placeholder?).
  class AgentConfigSync
    Result = Struct.new(:role, :agent_id, :in_sync, :remote_digest, :canonical_digest, keyword_init: true)

    def initialize(adapter: AiCalls::Providers::ElevenlabsAdapter.new)
      @adapter = adapter
    end

    def check(role)
      baseline = AiCalls::AgentConfigs::Baseline.for(role)
      agent_id = require_agent_id!(baseline)

      build_result(baseline:, agent_id:)
    end

    def sync!(role, confirm_production: false)
      baseline = AiCalls::AgentConfigs::Baseline.for(role)
      agent_id = require_agent_id!(baseline)
      refuse_unconfirmed_production!(confirm_production:)
      refuse_placeholder_in_production!(baseline)

      @adapter.update_agent_config(agent_id:, config: baseline.config)

      build_result(baseline:, agent_id:)
    end

    private

    def build_result(baseline:, agent_id:)
      remote_config = @adapter.fetch_agent_config(agent_id:)
      remote_digest = baseline.digest_for_remote(remote_config)

      Result.new(
        role: baseline.role, agent_id:, in_sync: remote_digest == baseline.digest,
        remote_digest:, canonical_digest: baseline.digest
      )
    end

    def require_agent_id!(baseline)
      agent_id = baseline.agent_id
      raise AiCallProviderUnavailableError if agent_id.blank?

      agent_id
    end

    def refuse_unconfirmed_production!(confirm_production:)
      return unless Rails.env.production?
      return if confirm_production

      raise AgentConfigSyncError, 'Refusing to sync agent config in production without explicit confirmation'
    end

    def refuse_placeholder_in_production!(baseline)
      return unless Rails.env.production?
      return unless baseline.placeholder?

      raise AgentConfigSyncError,
            "Refusing to sync the #{baseline.role} baseline into production: its prompt is still " \
            'the unapproved placeholder (config/locales/api.en.yml)'
    end
  end
end
