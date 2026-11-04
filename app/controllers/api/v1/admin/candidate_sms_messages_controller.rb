# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff send one SMS to a candidate by hand -- any message with a
      # send.pk template, in English or Urdu -- and see every SMS the candidate
      # was sent, automatic and manual. Index+create only: a delivery's outcome
      # is written by CandidateSms::DeliveryJob.
      class CandidateSmsMessagesController < ProtectedStaffController
        include IdempotentRequestHandling

        HISTORY_LIMIT = 50

        # The messages this candidate can be sent, the language to preselect, and the SMS history.
        def index
          authorize ::CandidateSmsDelivery, policy_class: ::Admin::CandidateSmsMessagePolicy

          render_success(data: {
                           default_locale: ::CandidateSms::ScheduleDelivery.locale_for(candidate),
                           messages: ::CandidateSms::SendManual.sendable_templates.map do |template|
                             ::Admin::CandidateSmsMessages::SendableMessageSerializer.new(template, candidate:).as_json
                           end,
                           deliveries: history.map { |delivery| serialized(delivery) }
                         })
        end

        # Sends the chosen message, idempotently.
        def create
          authorize ::CandidateSmsDelivery, policy_class: ::Admin::CandidateSmsMessagePolicy

          render_idempotent_response(scope: 'admin.candidate_sms_messages.create', subject: current_user,
                                     required: true) do
            delivery = ::CandidateSms::SendManual.call(candidate:, actor: current_user, **message_params)
            success_payload(data: serialized(delivery), status: :created)
          end
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def history
          ::CandidateSmsDelivery.where(candidate:).includes(:sent_by).order(created_at: :desc).limit(HISTORY_LIMIT)
        end

        def message_params
          permitted = params.expect(sms_message: [:message_code, :locale, { variables: {} }])
          { message_code: permitted[:message_code], locale: permitted[:locale],
            variables: permitted[:variables].to_h }
        end

        def serialized(delivery) = ::Admin::CandidateSmsMessages::DeliverySerializer.new(delivery).as_json
      end
    end
  end
end
