# frozen_string_literal: true

class StaffInvitationMailer < ApplicationMailer
  def invitation_email
    @user = params.fetch(:user)
    @invitation_token = params.fetch(:invitation_token)
    @expires_in_hours = (User::INVITATION_TTL / 1.hour).to_i

    mail(to: @user.email, subject: I18n.t('api.users.mailer.subject'))
  end
end
