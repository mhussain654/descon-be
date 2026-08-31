# frozen_string_literal: true

module CandidateWorkflows
  # rubocop:disable Metrics/ClassLength
  class SnapshotBuilder < ApplicationService
    def initialize(assignment:, candidate_status:, stages:, include_history_actor: false)
      @assignment = assignment
      @candidate_status = candidate_status
      @stages = stages
      @include_history_actor = include_history_actor
    end

    def call
      snapshot.merge(progress_attributes)
    end

    private

    def snapshot
      {
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
        total_count: @stages.length,
        progress_percentage: progress_percentage
      }
    end

    def current_stage = @assignment&.current_workflow_stage

    def current_position = current_stage&.position

    def stage_histories
      @stage_histories ||= loaded_stage_histories
    end

    def history_by_stage_code
      @history_by_stage_code ||= stage_histories.index_by { |history_entry| history_entry.to_workflow_stage.code }
    end

    def history_from_stage_code
      @history_from_stage_code ||= stage_histories.index_by { |history_entry| history_entry.from_workflow_stage&.code }
    end

    def current_stage_hash = current_stage.present? ? serialize_stage(current_stage, status: current_stage_status) : nil

    def timeline = @stages.map { |stage| serialize_stage(stage, status: timeline_status_for(stage)) }

    def history
      stage_histories.map do |history_entry|
        {
          from_stage: history_entry.from_workflow_stage && stage_reference(history_entry.from_workflow_stage),
          to_stage: stage_reference(history_entry.to_workflow_stage),
          occurred_at: history_entry.occurred_at.utc.iso8601,
          reason_code: history_entry.reason_code,
          details: history_entry.metadata.presence
        }.compact
      end
    end

    def serialize_stage(stage, status:)
      {
        code: stage.code,
        name: stage.name_for,
        position: stage.position,
        status:
      }.merge(timestamp_attributes_for(stage, status:))
    end

    def timestamp_attributes_for(stage, status:)
      case status
      when 'completed'
        { completed_at: completed_at_for(stage)&.utc&.iso8601 }.compact
      when 'current'
        { started_at: started_at_for(stage)&.utc&.iso8601 }.compact
      else
        {}
      end
    end

    def completed_at_for(stage)
      return history_by_stage_code[stage.code]&.occurred_at if terminal_stage?(stage) && terminal_workflow?

      history_from_stage_code[stage.code]&.occurred_at
    end

    def started_at_for(stage)
      return @assignment&.created_at if stage.code == WorkflowStage.registered.code

      history_by_stage_code[stage.code]&.occurred_at
    end

    def timeline_status_for(stage)
      return 'pending' if current_position.blank?
      return 'completed' if terminal_workflow? && stage.position <= current_position
      return 'completed' if stage.position < current_position
      return 'current' if stage.position == current_position

      'pending'
    end

    def stage_reference(stage) = { code: stage.code, name: stage.name_for, position: stage.position }

    def completed_count
      return 0 if current_position.blank?

      terminal_workflow? ? current_position : current_position - 1
    end

    def progress_percentage
      return 0 if completed_count.zero? || @stages.empty?

      ((completed_count * 100.0) / @stages.length).floor
    end

    def serialized_updated_at
      updated_at = @assignment&.updated_at
      updated_at&.utc&.iso8601
    end

    def loaded_stage_histories
      return [] if @assignment.blank?

      relation = @assignment
                 .candidate_stage_histories
                 .includes(:from_workflow_stage, :to_workflow_stage)
                 .order(:occurred_at, :id)
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

    def terminal_workflow? = terminal_stage?(current_stage)

    def terminal_stage?(stage)
      stage&.code == 'mobilized'
    end
  end
  # rubocop:enable Metrics/ClassLength
end
