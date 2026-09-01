# frozen_string_literal: true

class AddHostedCheckoutFieldsToPayments < ActiveRecord::Migration[8.1]
  def change
    add_checkout_fields
    add_checkout_indexes
    add_checkout_constraints
  end

  private

  def add_checkout_fields
    change_table :payments, bulk: true do |t|
      string_checkout_fields.each { |field| t.string field }
      datetime_checkout_fields.each { |field| t.datetime field }
    end
  end

  def string_checkout_fields
    %i[
      provider_code
      provider_order_id
      provider_session_id
      provider_transaction_id
      provider_status_code
      provider_response_code
      checkout_url
    ]
  end

  def datetime_checkout_fields
    %i[checkout_expires_at last_provider_event_at]
  end

  def add_checkout_indexes
    add_index :payments, :provider_order_id, unique: true
    add_index :payments, :provider_session_id, unique: true
    add_index :payments, :provider_transaction_id
  end

  def add_checkout_constraints
    add_check_constraint :payments,
                         "provider_code IS NULL OR provider_code ~ '^[a-z0-9_]+$'",
                         name: 'payments_provider_code_format'
  end
end
