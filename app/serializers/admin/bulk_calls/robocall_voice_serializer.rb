# frozen_string_literal: true

module Admin
  module BulkCalls
    class RobocallVoiceSerializer
      def initialize(voice)
        @voice = voice
      end

      def as_json(*)
        {
          id: @voice.public_id, name_en: @voice.name_en, name_ur: @voice.name_ur, voice_id: @voice.voice_id,
          active: @voice.active, updated_at: @voice.updated_at.utc.iso8601
        }
      end
    end
  end
end
