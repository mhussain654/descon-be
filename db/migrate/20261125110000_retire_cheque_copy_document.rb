# frozen_string_literal: true

# The Cheque Copy checklist item is retired: the Bank Account Details form
# already asks for a cheque as its proof, so candidates were uploading the same
# cheque twice. The document type and every requirement row for it (including
# any project- or craft-specific ones) are deactivated, never deleted, so cheque
# copies already uploaded stay stored and visible to staff. Verification then
# no longer waits for a cheque copy; the bank details are still required.
class RetireChequeCopyDocument < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE document_types SET active = false, updated_at = NOW() WHERE code = 'cheque_copy'"
    update_requirements('active = false')
  end

  # Brings back the type and the catalog's common row only: which project- or
  # craft-specific rows were active before is not recorded.
  def down
    execute "UPDATE document_types SET active = true, updated_at = NOW() WHERE code = 'cheque_copy'"
    update_requirements('active = true', 'AND project_id IS NULL AND craft_id IS NULL AND country_id IS NULL')
  end

  private

  def update_requirements(assignment, scope = '')
    execute <<~SQL.squish
      UPDATE document_requirements SET #{assignment}, updated_at = NOW()
      WHERE document_type_id IN (SELECT id FROM document_types WHERE code = 'cheque_copy') #{scope}
    SQL
  end
end
