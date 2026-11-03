# frozen_string_literal: true

module MobilizationProcesses
  # Moves every candidate assignment still attached to a retired process onto
  # its country's current process, restarting it at that process's first
  # stage. Meant for the one-off switch to the client's finalized country
  # flows while only test candidates exist: an earlier version's progress has
  # no meaning in the new flow, so it is not carried over. Stage histories
  # stay as they were (they keep their own process reference) and each move is
  # audited. Idempotent -- an assignment already on an active process is left
  # alone, so running it again changes nothing.
  class RestartOnCurrentProcessService < ApplicationService
    ACTION_CODE = 'candidate_mobilization_process_restarted'

    def call
      assignments_on_retired_processes.find_each.map { |assignment| restart!(assignment) }
    end

    private

    def assignments_on_retired_processes
      CandidateAssignment.joins(:mobilization_process).where.not(mobilization_processes: { status: 'active' })
                         .includes(:candidate, :country, :mobilization_process)
    end

    def restart!(assignment)
      previous = assignment.mobilization_process
      current = MobilizationProcess.resolve_for(assignment.country)
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
