# frozen_string_literal: true

module MobilizationProcesses
  # Moves every candidate assignment that isn't on its country's current
  # process -- one still on a retired version, or one on the common process
  # although its country now has its own flow -- onto that process,
  # restarting it at the first stage. Meant for the one-off switch to the
  # client's finalized country flows while only test candidates exist: an earlier version's progress has
  # no meaning in the new flow, so it is not carried over. Stage histories
  # stay as they were (they keep their own process reference) and each move is
  # audited. Idempotent -- an assignment already on its country's current
  # process is left alone, so running it again changes nothing.
  class RestartOnCurrentProcessService < ApplicationService
    ACTION_CODE = 'candidate_mobilization_process_restarted'

    def call
      CandidateAssignment.includes(:candidate, :country, :mobilization_process).find_each.filter_map do |assignment|
        current = current_process_for(assignment.country)
        restart!(assignment, current) unless assignment.mobilization_process_id == current.id
      end
    end

    private

    def current_process_for(country)
      @current_processes ||= {}
      @current_processes[country&.id] ||= MobilizationProcess.resolve_for(country)
    end

    def restart!(assignment, current)
      previous = assignment.mobilization_process
      first_stage = current.first_stage

      CandidateAssignment.transaction do
        assignment.update!(mobilization_process: current, current_workflow_stage: first_stage.workflow_stage,
                           current_mobilization_process_stage: first_stage)
        assignment.candidate.update!(status_code: first_stage.code)
        record_audit!(assignment, previous, current)
      end
      assignment
    end

    def record_audit!(assignment, previous, current)
      AuditEvent.create!(
        candidate: assignment.candidate, candidate_assignment: assignment,
        entity_type: 'CandidateAssignment', entity_id: assignment.id, action_code: ACTION_CODE,
        metadata: {
          candidate_assignment_public_id: assignment.public_id,
          from_process: "#{previous.code} v#{previous.version}", to_process: "#{current.code} v#{current.version}"
        },
        occurred_at: Time.current
      )
    end
  end
end
