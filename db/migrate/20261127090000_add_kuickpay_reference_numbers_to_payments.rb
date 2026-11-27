# frozen_string_literal: true

# KuickPay's insert-voucher reply carries its reference number (the
# "ReferenceNumber" column of KuickPay's portal) with the institution code in
# front, e.g. 10420 + 261105039065. Both forms are kept on the voucher payment:
# `kuickpay_reference_number` as the portal shows it, for staff to look the
# voucher up, and `kuickpay_company_reference_number` exactly as returned.
# Vouchers issued earlier are filled from the reply already stored in their
# voucher_created event.
class AddKuickpayReferenceNumbersToPayments < ActiveRecord::Migration[8.1]
  def up
    change_table :payments, bulk: true do |t|
      t.string :kuickpay_reference_number, limit: 40
      t.string :kuickpay_company_reference_number, limit: 40
    end
    add_index :payments, :kuickpay_reference_number, where: 'kuickpay_reference_number IS NOT NULL'
    backfill_from_voucher_events
  end

  def down
    remove_index :payments, :kuickpay_reference_number
    change_table :payments, bulk: true do |t|
      t.remove :kuickpay_reference_number, :kuickpay_company_reference_number
    end
  end

  private

  def backfill_from_voucher_events
    institution_id = Payments::Configuration.new.kuickpay_institution_id.to_s
    select_rows(<<~SQL.squish).each { |payment_id, returned| backfill(payment_id, returned, institution_id) }
      SELECT DISTINCT ON (payment_id) payment_id, payload -> 'body' ->> 'response_description'
      FROM payment_events
      WHERE event_type = 'voucher_created' AND payload -> 'body' ->> 'response_description' IS NOT NULL
      ORDER BY payment_id, created_at DESC
    SQL
  end

  def backfill(payment_id, returned, institution_id)
    reference = Payments::Providers::KuickpayReferenceNumber.without_institution(returned, institution_id)
    execute(<<~SQL.squish)
      UPDATE payments
      SET kuickpay_reference_number = #{quote(reference)}, kuickpay_company_reference_number = #{quote(returned)}
      WHERE id = #{payment_id.to_i} AND kuickpay_company_reference_number IS NULL
    SQL
  end
end
