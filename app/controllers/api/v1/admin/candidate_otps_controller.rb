# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Developer-only OTP tab on the candidate page: the sign-in codes sent to
      # the candidate, and sending a new one in English or Urdu whose code is
      # returned once so the developer can read it out (see
      # CandidateAuthentication::Otp::StaffSendService). Deliberately not
      # idempotent-replayed: a stored replay would keep the plain code.
      class CandidateOtpsController < ProtectedStaffController
        HISTORY_LIMIT = 20

        def index
          authorize ::CandidateOtpChallenge, policy_class: ::Admin::CandidateOtpPolicy

          response.set_header('Cache-Control', 'private, no-store')
          render_success(data: {
                           default_locale: candidate.communication_locale,
                           sender_name: ::Sms::Configuration.new.sendpk_sender_id(candidate.sms_sender),
                           otps: history.map { |challenge| serialized(challenge) }
                         })
        end

        def create
          authorize ::CandidateOtpChallenge, policy_class: ::Admin::CandidateOtpPolicy

          result = ::CandidateAuthentication::Otp::StaffSendService.call(
            candidate:, actor: current_user, locale: params.expect(otp: [:locale])[:locale],
            request_id: request.request_id
          )
          response.set_header('Cache-Control', 'private, no-store')
          render_success(data: created_payload(result), status: :created)
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def history
          ::CandidateOtpChallenge.where(candidate:).includes(:sent_by).order(created_at: :desc).limit(HISTORY_LIMIT)
        end

        def created_payload(result)
          serialized(result.fetch(:challenge)).merge(
            code: result.fetch(:code), sms_sent: result.fetch(:sms_sent), sms_error_code: result.fetch(:sms_error_code)
          )
        end

        def serialized(challenge) = ::Admin::CandidateOtps::ChallengeSerializer.new(challenge).as_json
      end
    end
  end
end
