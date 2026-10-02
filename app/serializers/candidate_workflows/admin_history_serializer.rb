# frozen_string_literal: true

module CandidateWorkflows
  class AdminHistorySerializer
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def as_json(*)
      {
        candidate_id: @snapshot.candidate.public_id,
        assignment_id: @snapshot.assignment&.public_id,
        history: serialized_history,
        updated_at: @snapshot.updated_at
      }
    end

    private

    def serialized_history
      @snapshot.history_entries.map do |history_entry|
        {
          from_stage: HistoryStageReference.from(history_entry),
          to_stage: HistoryStageReference.to(history_entry),
          occurred_at: history_entry.occurred_at.utc.iso8601,
          reason_code: history_entry.reason_code,
          details: history_entry.metadata.presence,
          actor: serialized_actor(history_entry.actor)
        }.compact
      end
    end

    def serialized_actor(actor)
      return if actor.blank?

      { id: actor.public_id, role: actor.role }
    end
  end
end
