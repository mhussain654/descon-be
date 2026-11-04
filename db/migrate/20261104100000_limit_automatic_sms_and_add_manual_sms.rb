# frozen_string_literal: true

# Client decision (Nov 2026): only three SMS go out automatically -- all
# documents submitted, visa issued and ticket ready for handover. Every other
# message stays available for staff to send by hand from the candidate page.
#
# - adds the new "documents_submitted" message (allowed by the check constraint,
#   with its sms_templates row switched on);
# - switches automatic sending on for the three and off for every other
#   progress SMS (the OTP is untouched);
# - records which staff member sent a manual SMS;
# - adds the send_candidate_sms permission for the roles that can already call
#   a candidate (deploys do not run the seeds).
class LimitAutomaticSmsAndAddManualSms < ActiveRecord::Migration[8.1]
  OLD_CODES = %w[
    otp registered document_rejected medical_appointment fee_pending medical_unfit qvc_appointment
    visa_issued visa_rejected protection_call ticket_handover flight_details
  ].freeze
  NEW_CODES = (OLD_CODES + %w[documents_submitted]).freeze
  AUTOMATIC_CODES = %w[documents_submitted visa_issued ticket_handover].freeze
  PERMISSION_CODE = 'send_candidate_sms'
  PERMISSION_ROLES = %w[admin developer hr mps].freeze

  def up
    add_reference :candidate_sms_deliveries, :sent_by, foreign_key: { to_table: :users }
    replace_message_code_constraint(NEW_CODES)
    add_documents_submitted_template
    execute <<~SQL.squish
      UPDATE sms_templates SET enabled = (message_code IN (#{quoted(AUTOMATIC_CODES)})), updated_at = NOW()
      WHERE message_code <> 'otp'
    SQL
    add_permission
  end

  def down
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (SELECT id FROM permissions WHERE code = '#{PERMISSION_CODE}')
    SQL
    execute "DELETE FROM permissions WHERE code = '#{PERMISSION_CODE}'"
    execute "DELETE FROM sms_templates WHERE message_code = 'documents_submitted'"
    replace_message_code_constraint(OLD_CODES)
    remove_reference :candidate_sms_deliveries, :sent_by, foreign_key: { to_table: :users }
  end

  private

  def replace_message_code_constraint(codes)
    remove_check_constraint :sms_templates, name: 'sms_templates_message_code_known'
    add_check_constraint :sms_templates, "message_code IN (#{quoted(codes)})", name: 'sms_templates_message_code_known'
  end

  def add_documents_submitted_template
    execute <<~SQL.squish
      INSERT INTO sms_templates (message_code, enabled, created_at, updated_at)
      VALUES ('documents_submitted', TRUE, NOW(), NOW())
      ON CONFLICT (message_code) DO NOTHING
    SQL
  end

  def add_permission
    execute <<~SQL.squish
      INSERT INTO permissions (code, active, system_defined, created_at, updated_at)
      VALUES ('#{PERMISSION_CODE}', TRUE, TRUE, NOW(), NOW())
      ON CONFLICT (code) DO NOTHING
    SQL
    grant_permission
  end

  def grant_permission
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, NOW(), NOW()
      FROM roles CROSS JOIN permissions
      WHERE roles.code IN (#{quoted(PERMISSION_ROLES)}) AND permissions.code = '#{PERMISSION_CODE}'
      ON CONFLICT DO NOTHING
    SQL
  end

  def quoted(codes) = codes.map { |code| connection.quote(code) }.join(', ')
end
