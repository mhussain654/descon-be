# frozen_string_literal: true

# Adds the three "your appointment / flight has changed" SMS messages, sent when
# a developer corrects a candidate's medical appointment, QVC appointment or
# flight details and leaves "Send SMS to candidate" ticked. Their template ids
# are left empty for a developer to fill in App Settings; until then they are
# not sent.
class AddWorkflowChangeSms < ActiveRecord::Migration[8.1]
  OLD_CODES = %w[
    otp registered document_rejected medical_appointment fee_pending medical_unfit qvc_appointment
    visa_issued visa_rejected protection_call ticket_handover flight_details documents_submitted
    ticket_and_flight_details
  ].freeze
  NEW_CODES = %w[medical_appointment_changed qvc_appointment_changed flight_details_changed].freeze

  def up
    replace_message_code_constraint(OLD_CODES + NEW_CODES)
    NEW_CODES.each do |code|
      execute <<~SQL.squish
        INSERT INTO sms_templates (message_code, enabled, created_at, updated_at)
        VALUES (#{connection.quote(code)}, TRUE, NOW(), NOW())
        ON CONFLICT (message_code) DO NOTHING
      SQL
    end
  end

  def down
    execute "DELETE FROM sms_templates WHERE message_code IN (#{quoted(NEW_CODES)})"
    replace_message_code_constraint(OLD_CODES)
  end

  private

  def quoted(codes) = codes.map { |code| connection.quote(code) }.join(', ')

  def replace_message_code_constraint(codes)
    remove_check_constraint :sms_templates, name: 'sms_templates_message_code_known'
    add_check_constraint :sms_templates, "message_code IN (#{quoted(codes)})",
                         name: 'sms_templates_message_code_known'
  end
end
