# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261112100000_add_ticket_and_flight_details_sms')

RSpec.describe AddTicketAndFlightDetailsSms do
  subject(:migration) { described_class.new }

  # The seeded test database (CI runs db:prepare) already has every SMS, so each example starts from an
  # empty table. The example's transaction puts the rows back.
  around do |example|
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Base.connection.execute('DELETE FROM sms_templates')
      migration.down
      example.run
    end
  end

  it 'adds the ticket and flight details SMS, switched on with no template ids yet' do
    migration.up

    expect(SmsTemplate.find_by!(message_code: 'ticket_and_flight_details'))
      .to have_attributes(enabled: true, template_id_en: nil, template_id_ur: nil)
  end

  it 'reverses cleanly, refusing the message again' do
    migration.up
    migration.down

    expect(SmsTemplate.exists?(message_code: 'ticket_and_flight_details')).to be(false)
    expect { insert_row_in_savepoint }.to raise_error(ActiveRecord::StatementInvalid)
    migration.up
  end

  # A savepoint, so the refused insert does not abort the example's transaction.
  def insert_row_in_savepoint
    SmsTemplate.transaction(requires_new: true) do
      SmsTemplate.insert_all([{ message_code: 'ticket_and_flight_details', enabled: true }]) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
