# frozen_string_literal: true

# RoboCall.pk plays a fixed, pre-recorded voice per call: a call needs only a
# voice id, not a script. So a workflow stage's call script gains a `voice_id`
# (its announcement text becomes optional -- only the ElevenLabs provider
# reads it), and each call records the provider's own call id (polled for its
# result, since RoboCall has no webhooks) and the voice that was played.
class AddRobocallSupportToAiCalls < ActiveRecord::Migration[8.1]
  def change
    change_table :workflow_stage_call_scripts, bulk: true do |t|
      t.string :voice_id
      t.change_null :announcement_en, true
    end

    change_table :candidate_ai_calls, bulk: true do |t|
      t.string :robocall_call_id
      t.string :provider_voice_id
      t.index :robocall_call_id, unique: true, where: 'robocall_call_id IS NOT NULL',
                                 name: 'index_candidate_ai_calls_on_robocall_call_id'
    end
  end
end
