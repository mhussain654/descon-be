# frozen_string_literal: true

namespace :ai_calls do
  namespace :agent_config do
    desc 'Reports whether the published ElevenLabs agent config for ROLE (outbound|inbound) matches ' \
         'the repo-committed canonical baseline (AiCalls::AgentConfigs::Baseline). Read-only, safe to ' \
         'run in any environment.'
    task :check, [:role] => :environment do |_task, args|
      role = args[:role]
      abort('Usage: bin/rails "ai_calls:agent_config:check[outbound|inbound]"') if role.blank?

      result = run_agent_config_sync(role) { |sync| sync.check(role) }
      report_agent_config_sync_result(result)
    end

    desc 'Pushes the repo-committed canonical baseline for ROLE (outbound|inbound) to ElevenLabs and ' \
         'verifies the result. Refuses to run against production unless CONFIRM_PRODUCTION_SYNC=true ' \
         'is set, and always refuses while the baseline prompt is still the unapproved placeholder.'
    task :sync, [:role] => :environment do |_task, args|
      role = args[:role]
      abort('Usage: bin/rails "ai_calls:agent_config:sync[outbound|inbound]"') if role.blank?

      confirm_production = ActiveModel::Type::Boolean.new.cast(ENV.fetch('CONFIRM_PRODUCTION_SYNC', 'false'))
      result = run_agent_config_sync(role) { |sync| sync.sync!(role, confirm_production:) }
      puts "Pushed baseline config to agent #{result.agent_id} (role: #{result.role})."
      report_agent_config_sync_result(result)
    end
  end
end

def run_agent_config_sync(role)
  puts "Target agent role: #{role}"
  yield(AiCalls::AgentConfigSync.new)
rescue ArgumentError, AiCalls::AgentConfigSyncError, AiCallProviderUnavailableError, AiCallProviderRequestError => e
  abort("Failed: #{e.message}")
end

def report_agent_config_sync_result(result)
  if result.in_sync
    puts "OK: agent #{result.agent_id} (#{result.role}) matches the canonical baseline " \
         "(digest #{result.canonical_digest})."
  else
    puts "DRIFT: agent #{result.agent_id} (#{result.role}) does not match the canonical baseline."
    puts "  remote digest:    #{result.remote_digest}"
    puts "  canonical digest: #{result.canonical_digest}"
  end
end
