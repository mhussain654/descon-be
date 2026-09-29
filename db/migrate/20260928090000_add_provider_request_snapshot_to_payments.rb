# frozen_string_literal: true

# KuickPay's hosted-checkout Status API (POST /api/status) does not
# regenerate a signature for the merchant -- it re-validates the exact
# request used to create the session. The orderid/amount/timestamp/signature
# sent there must be byte-for-byte identical to what was sent to
# POST /checkout/api/session, so those exact values (not recomputed ones)
# must be persisted at session-creation time and read back later, per
# KuickPay's own integration guide ("Persist these values right after
# session creation, then read them back -- rather than recomputing or
# reconstructing them -- when calling the Status API").
#
# Nullable and provider-agnostic in name only for schema simplicity -- in
# practice only ever populated for provider_code == 'kuickpay'; every other
# provider (mock_hosted_checkout) leaves these null.
class AddProviderRequestSnapshotToPayments < ActiveRecord::Migration[8.1]
  def change
    change_table :payments, bulk: true do |t|
      t.column :provider_request_timestamp, :string
      t.column :provider_request_signature, :string
      t.column :provider_amount_payable, :string
    end
  end
end
