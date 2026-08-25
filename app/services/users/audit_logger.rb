# frozen_string_literal: true

module Users
  class AuditLogger < ApplicationService
    def initialize(**attributes)
      @action_code = attributes.fetch(:action_code)
      @actor = attributes.fetch(:actor)
      @target = attributes.fetch(:target)
      @request_id = attributes.fetch(:request_id)
      @changes = attributes.fetch(:changes)
      @reason_code = attributes[:reason_code]
    end

    def call
      AuditEvent.create!(
        actor: @actor,
        entity_type: 'User',
        entity_id: @target.id,
        action_code: @action_code,
        reason_code: @reason_code,
        request_id: @request_id,
        metadata: metadata,
        occurred_at: Time.current
      )
    end

    private

    def metadata
      {
        target_public_id: @target.public_id,
        before: @changes[:before].presence,
        after: @changes[:after].presence
      }.compact
    end
  end
end
