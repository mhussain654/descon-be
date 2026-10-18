# frozen_string_literal: true

# RoboCall.pk plays a fixed, pre-recorded voice per call: a call needs only a
# voice id, not a script. So a workflow stage's call script gains a `voice_id`
# (its announcement text becomes optional -- only the ElevenLabs provider
# reads it), and each call records the provider's own call id (polled for its
# result, since RoboCall has no webhooks) and the voice that was played.
class AddRobocallSupportToAiCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_stage_call_scripts, :voice_id, :string
    change_column_null :workflow_stage_call_scripts, :announcement_en, true

    add_column :candidate_ai_calls, :robocall_call_id, :string
    add_column :candidate_ai_calls, :provider_voice_id, :string
    add_index :candidate_ai_calls, :robocall_call_id, unique: true, where: 'robocall_call_id IS NOT NULL',
                                                       name: 'index_candidate_ai_calls_on_robocall_call_id'
  end
end
