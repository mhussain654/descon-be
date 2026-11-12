# frozen_string_literal: true

# Adds the "ticket and flight details" SMS (client decision, Nov 2026): sent automatically when a candidate
# enters Protection Day, the step before the ticket, asking them to check MPS Connect for their ticket
# collection and flight details. A message of its own, so the existing "ticket handed over" SMS keeps its
# stage. Its template ids are left empty for a developer to fill in App Settings; until then it is not sent.
class AddTicketAndFlightDetailsSms < ActiveRecord::Migration[8.1]
  OLD_CODES = %w[
    otp registered document_rejected medical_appointment fee_pending medical_unfit qvc_appointment
    visa_issued visa_rejected protection_call ticket_handover flight_details documents_submitted
  ].freeze
  NEW_CODE = 'ticket_and_flight_details'

  def up
    replace_message_code_constraint(OLD_CODES + [NEW_CODE])
    execute <<~SQL.squish
      INSERT INTO sms_templates (message_code, enabled, created_at, updated_at)
      VALUES (#{connection.quote(NEW_CODE)}, TRUE, NOW(), NOW())
      ON CONFLICT (message_code) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM sms_templates WHERE message_code = #{connection.quote(NEW_CODE)}"
    replace_message_code_constraint(OLD_CODES)
  end

  private

  def replace_message_code_constraint(codes)
    remove_check_constraint :sms_templates, name: 'sms_templates_message_code_known'
    add_check_constraint :sms_templates, "message_code IN (#{codes.map { |code| connection.quote(code) }.join(', ')})",
                         name: 'sms_templates_message_code_known'
  end
end
