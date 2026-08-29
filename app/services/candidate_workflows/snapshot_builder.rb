# frozen_string_literal: true

module CandidateWorkflows
  class SnapshotBuilder < ApplicationService
    def initialize(assignment:, candidate_status:, stages:)
      @assignment = assignment
      @candidate_status = candidate_status
      @stages = stages
    end

    def call
      {
        current_stage: current_stage_hash,
        timeline:,
        history:,
        completed_count: current_position || 0,
        total_count: @stages.length,
        progress_percentage: progress_percentage,
        updated_at: serialized_updated_at
      }
    end

    private

    def current_stage = @assignment&.current_workflow_stage

    def current_position = current_stage&.position

    def stage_histories
      @stage_histories ||= loaded_stage_histories
    end

    def history_by_stage_code
      @history_by_stage_code ||= stage_histories.index_by { |history_entry| history_entry.to_workflow_stage.code }
    end

    def current_stage_hash
      return if current_stage.blank?

      serialize_stage(current_stage, status: 'current')
    end

    def timeline
      @stages.map { |stage| serialize_stage(stage, status: timeline_status_for(stage)) }
    end

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
        status:,
        completed_at: completed_at_for(stage)&.utc&.iso8601
      }.compact
    end

    def completed_at_for(stage)
      history_entry = history_by_stage_code[stage.code]
      return history_entry.occurred_at if history_entry.present?
      return @assignment&.created_at if stage.code == WorkflowStage.registered.code && current_position.present?

      nil
    end

    def timeline_status_for(stage)
      return 'pending' if current_position.blank?
      return 'completed' if stage.position < current_position
      return 'current' if stage.position == current_position

      'pending'
    end

    def stage_reference(stage) = { code: stage.code, name: stage.name_for, position: stage.position }

    def progress_percentage
      return 0 if current_position.blank? || @stages.empty?

      ((current_position * 100.0) / @stages.length).floor
    end

    def serialized_updated_at
      return if @assignment.blank? || @assignment.updated_at.blank?

      @assignment.updated_at.utc.iso8601
    end

    def loaded_stage_histories
      return [] if @assignment.blank?

      @assignment
        .candidate_stage_histories
        .includes(:from_workflow_stage, :to_workflow_stage)
        .order(:occurred_at, :id)
        .to_a
    end
  end
end
