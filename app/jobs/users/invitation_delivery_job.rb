# frozen_string_literal: true

module Users
  class InvitationDeliveryJob < ApplicationJob
    queue_as :default

    retry_on InvitationDelivery::DeliveryError, wait: 10.seconds, attempts: 3

    def perform(user_id)
      InvitationDelivery.call(user_id:)
    end
  end
end
