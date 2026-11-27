# frozen_string_literal: true

# Developer-set KuickPay voucher dates (App Settings): the due date is the
# issue date + voucher_due_days, and the expiry date (the last day KuickPay
# accepts payment, and the day our voucher closes) is the due date +
# voucher_grace_days, as the client's portal vouchers do (expiry usually two
# days after the due date). Replaces the PAYMENT_VOUCHER_VALID_DAYS server
# setting. Each voucher payment keeps its own due date for KuickPay's SMS.
class AddVoucherDaysToAppFeatureSettings < ActiveRecord::Migration[8.1]
  def change
    change_table :app_feature_settings, bulk: true do |t|
      t.integer :voucher_due_days, null: false, default: 15
      t.integer :voucher_grace_days, null: false, default: 2
      t.check_constraint 'voucher_due_days BETWEEN 1 AND 60', name: 'app_feature_settings_voucher_due_days_range'
      t.check_constraint 'voucher_grace_days BETWEEN 0 AND 15', name: 'app_feature_settings_voucher_grace_days_range'
    end
    add_column :payments, :voucher_due_on, :date
  end
end
