# frozen_string_literal: true

# Adds the developer-only `view_job_logs` permission (reading background job
# runs and failures on the admin Job logs page) and grants it to the developer
# role, so existing databases get it without re-running the seeds. db/seeds.rb
# grants it the same way on a fresh database.
class AddViewJobLogsPermission < ActiveRecord::Migration[8.1]
  CODE = 'view_job_logs'

  def up
    execute <<~SQL.squish
      INSERT INTO permissions (code, system_defined, active, created_at, updated_at)
      VALUES (#{connection.quote(CODE)}, TRUE, TRUE, NOW(), NOW())
      ON CONFLICT (code) DO NOTHING
    SQL
    grant_to_developer
  end

  def down
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (SELECT id FROM permissions WHERE code = #{connection.quote(CODE)})
    SQL
    execute "DELETE FROM permissions WHERE code = #{connection.quote(CODE)}"
  end

  private

  def grant_to_developer
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, NOW(), NOW()
      FROM roles CROSS JOIN permissions
      WHERE roles.code = 'developer' AND permissions.code = #{connection.quote(CODE)}
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end
end
