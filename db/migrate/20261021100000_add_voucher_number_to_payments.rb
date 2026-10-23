# frozen_string_literal: true

# A payment made with a KuickPay voucher (consumer) number instead of the hosted
# card checkout. The number is what the candidate pays from a wallet or bank app
# and what KuickPay's settlement inquiry reports back, so it must be unique.
# Existing rows have none; the voucher's expiry reuses `checkout_expires_at`.
class AddVoucherNumberToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :voucher_number, :string
    add_index :payments, :voucher_number, unique: true, where: 'voucher_number IS NOT NULL',
                                          name: 'index_payments_on_voucher_number'
  end
end
