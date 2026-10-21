# frozen_string_literal: true

module Api
  module V1
    module Admin
      # The call-type library: named RoboCall voices an admin picks from for a
      # bulk call. Index, create and update only -- a voice is switched off
      # (`active: false`), never deleted, so past batches keep their history.
      class RobocallVoicesController < ProtectedStaffController
        VOICE_PARAMS = %i[name_en name_ur voice_id active].freeze

        def index
          authorize ::RobocallVoice, policy_class: ::Admin::RobocallVoicePolicy

          render_success(data: voice_scope.ordered.map { |voice| serialized(voice) })
        end

        def create
          authorize ::RobocallVoice, policy_class: ::Admin::RobocallVoicePolicy

          voice = ::RobocallVoice.create!(voice_params.merge(created_by: current_user, updated_by: current_user))
          record_audit!(voice, 'robocall_voice_created')
          render_success(data: serialized(voice), status: :created)
        end

        def update
          authorize ::RobocallVoice, policy_class: ::Admin::RobocallVoicePolicy

          voice = voice_scope.find_by!(public_id: params.expect(:id))

          voice.update!(voice_params.merge(updated_by: current_user))
          record_audit!(voice, 'robocall_voice_updated')
          render_success(data: serialized(voice))
        end

        private

        def voice_scope
          policy_scope(::RobocallVoice, policy_scope_class: ::Admin::RobocallVoicePolicy::Scope)
        end

        def voice_params
          params.expect(robocall_voice: VOICE_PARAMS)
        end

        def record_audit!(voice, action_code)
          ::AuditEvent.create!(
            actor: current_user, entity_type: 'RobocallVoice', entity_id: voice.id, action_code:,
            request_id: request.request_id, occurred_at: Time.current,
            metadata: { name_en: voice.name_en, voice_id: voice.voice_id, active: voice.active }
          )
        end

        def serialized(voice)
          ::Admin::BulkCalls::RobocallVoiceSerializer.new(voice).as_json
        end
      end
    end
  end
end
