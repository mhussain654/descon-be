# frozen_string_literal: true

module CandidateWorkflows
  # Builds the workflow state for one assignment from its own mobilization
  # process: the timeline lists only that process's stages, positions are
  # places within it, the terminal stage is its last stage, and progress is
  # completed process stages / total process stages.
  # rubocop:disable Metrics/ClassLength
  class SnapshotBuilder < ApplicationService
    def initialize(assignment:, candidate_status:, include_history_actor: false)
      @assignment = assignment
      @candidate_status = candidate_status
      @include_history_actor = include_history_actor
    end

    def call
      snapshot.merge(progress_attributes)
    end

    private

    def snapshot
      {
        mobilization_process: @assignment&.mobilization_process,
        current_stage: current_stage_hash,
        timeline:,
        history:,
        history_entries: stage_histories,
        qvc_attempts: loaded_qvc_attempts,
        protection_record: loaded_protection_record,
        updated_at: serialized_updated_at
      }
    end

    def progress_attributes
      {
        completed_count:,
        total_count: process_stages.length,
        progress_percentage: progress_percentage
      }
    end

    def process_stages
      @process_stages ||=
        @assignment.present? ? @assignment.mobilization_process.stages.includes(:workflow_stage).to_a : []
    end

    def current_process_stage = @assignment&.current_mobilization_process_stage

    def current_position = current_process_stage&.position

    def stage_histories
      @stage_histories ||= loaded_stage_histories
    end

    def history_by_stage_code
      @history_by_stage_code ||= stage_histories.index_by(&:stage_code)
    end

    def history_from_stage_code
      @history_from_stage_code ||= stage_histories.index_by(&:from_stage_code)
    end

    def current_stage_hash
      current_process_stage.present? ? serialize_stage(current_process_stage, status: current_stage_status) : nil
    end

    def timeline = process_stages.map { |stage| serialize_stage(stage, status: timeline_status_for(stage)) }

    def history
      stage_histories.map do |history_entry|
        {
          from_stage: HistoryStageReference.from(history_entry),
          to_stage: HistoryStageReference.to(history_entry),
          occurred_at: history_entry.occurred_at.utc.iso8601,
          reason_code: history_entry.reason_code,
          details: history_entry.metadata.presence
        }.compact
      end
    end

    def serialize_stage(process_stage, status:)
      {
        code: process_stage.code,
        name: process_stage.workflow_stage.name_for,
        position: process_stage.position,
        action_type: process_stage.action_type,
        required: process_stage.required,
        status:
      }.merge(timestamp_attributes_for(process_stage, status:))
    end

    def timestamp_attributes_for(process_stage, status:)
      case status
      when 'completed'
        { completed_at: completed_at_for(process_stage)&.utc&.iso8601 }.compact
      when 'current'
        { started_at: started_at_for(process_stage)&.utc&.iso8601 }.compact
      else
        {}
      end
    end

    def completed_at_for(process_stage)
      if terminal_stage?(process_stage) && terminal_workflow?
        return history_by_stage_code[process_stage.code]&.occurred_at
      end

      history_from_stage_code[process_stage.code]&.occurred_at
    end

    def started_at_for(process_stage)
      return @assignment&.created_at if process_stage.code == WorkflowStage.registered.code

      history_by_stage_code[process_stage.code]&.occurred_at
    end

    def timeline_status_for(process_stage)
      return 'pending' if current_position.blank?
      return 'completed' if terminal_workflow? && process_stage.position <= current_position
      return 'completed' if process_stage.position < current_position
      return 'current' if process_stage.position == current_position

      'pending'
    end

    def completed_count
      return 0 if current_position.blank?

      terminal_workflow? ? current_position : current_position - 1
    end

    def progress_percentage
      return 0 if completed_count.zero? || process_stages.empty?

      ((completed_count * 100.0) / process_stages.length).floor
    end

    def serialized_updated_at
      updated_at = @assignment&.updated_at
      updated_at&.utc&.iso8601
    end

    def loaded_stage_histories
      return [] if @assignment.blank?

      # Entries are served from their own snapshot columns -- no stage joins needed.
      relation = @assignment.candidate_stage_histories.order(:occurred_at, :id)
      relation = relation.includes(:actor) if @include_history_actor
      relation.to_a
    end

    def loaded_qvc_attempts
      return [] if @assignment.blank?

      @assignment.candidate_qvc_attempts.ordered.to_a
    end

    def loaded_protection_record
      return if @assignment.blank?

      @assignment.candidate_protection_record
    end

    def current_stage_status = terminal_workflow? ? 'completed' : 'current'

    def terminal_workflow? = terminal_stage?(current_process_stage)

    def terminal_stage?(process_stage)
      process_stage.present? && process_stage.position == process_stages.last&.position
    end
  end
  # rubocop:enable Metrics/ClassLength
end
