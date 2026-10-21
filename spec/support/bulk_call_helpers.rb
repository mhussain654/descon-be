# frozen_string_literal: true

# Builds a candidate who is at `stage_code` (both the candidate's status and the
# current assignment's workflow stage), as the bulk-call specs need.
module BulkCallHelpers
  def candidate_at(stage_code, **attributes)
    candidate = create(:candidate, status_code: stage_code, **attributes)
    assignment = create(:candidate_assignment, candidate:,
                                               current_workflow_stage: WorkflowStage.find_by!(code: stage_code))
    [candidate, assignment]
  end

  # A call with `voice` already made for the assignment.
  def call_with_voice(assignment, voice, **attributes)
    communication = create(:communication, channel_code: 'ai_voice_call', candidate_assignment: assignment)
    create(:candidate_ai_call, communication:, candidate_assignment: assignment, candidate: assignment.candidate,
                               provider_code: 'robocall', provider_voice_id: voice.voice_id, **attributes)
  end

  # The settings a bulk call needs: RoboCall as provider, outbound on, all hours.
  def with_bulk_calling_enabled(&)
    with_env('AI_VOICE_PROVIDER' => 'robocall', 'AI_VOICE_OUTBOUND_ENABLED' => 'true',
             'AI_VOICE_CALLING_HOURS_START' => '0', 'AI_VOICE_CALLING_HOURS_END' => '24', &)
  end
end

RSpec.configure { |config| config.include BulkCallHelpers }
