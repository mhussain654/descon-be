# frozen_string_literal: true

# A candidate's KuickPay vouchers now share one Kuickpay ID (institution code +
# candidate id), so a later voucher (after one expires or is replaced) carries
# the same number. The voucher number stays indexed for settlement lookups.
class AllowSharedKuickpayIdsOnPayments < ActiveRecord::Migration[8.1]
  def up
    remove_index :payments, name: 'index_payments_on_voucher_number'
    add_index :payments, :voucher_number, name: 'index_payments_on_voucher_number',
                                          where: 'voucher_number IS NOT NULL'
  end

  def down
    remove_index :payments, name: 'index_payments_on_voucher_number'
    add_index :payments, :voucher_number, name: 'index_payments_on_voucher_number', unique: true,
                                          where: 'voucher_number IS NOT NULL'
  end
end
