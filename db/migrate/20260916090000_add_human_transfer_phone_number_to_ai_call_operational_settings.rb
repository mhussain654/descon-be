# frozen_string_literal: true

# The destination AiCalls::Tools transfer_to_number pushes into the
# ElevenLabs agent baseline (see AiCalls::AgentConfigs::Baseline) once the
# client confirms a real escalation number (previously blocked entirely --
# see Trello MPS-709). Grouped with the other operational knobs on this
# same singleton row: like those, it is business-tunable and not security/
# guardrail content, and it's at least as sensitive as the existing 5
# columns (it redirects a live candidate call to a real phone number), so
# it stays behind the same `manage_ai_call_settings` permission rather than
# a new one. Nullable -- omitted from the synced agent config entirely
# until a real number is set (see AgentConfigs::Baseline), so a fresh
# environment never risks pushing a placeholder destination into a live
# ElevenLabs agent.
class AddHumanTransferPhoneNumberToAiCallOperationalSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_call_operational_settings, :human_transfer_phone_number, :string
    add_check_constraint :ai_call_operational_settings,
                         "human_transfer_phone_number IS NULL OR human_transfer_phone_number ~ '^\\+?\\d{10,15}$'",
                         name: 'ai_call_operational_settings_human_transfer_phone_number_format'
  end
end
