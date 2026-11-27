# frozen_string_literal: true

# The assignment's text reference number (e.g. DES-500002) becomes an optional
# whole-number file number, unique within a campaign, that staff can set later.
# Existing values keep their digits (DES-500002 -> 500002); a value with no
# digits (e.g. STORE-REVIEW) becomes empty. If two assignments in one campaign
# would end up with the same number, the migration stops so staff can decide.
class ReplaceReferenceNumberWithFileNumber < ActiveRecord::Migration[8.1]
  MAX_DIGITS = 15

  def up
    add_column :candidate_assignments, :file_number, :bigint
    execute <<~SQL.squish
      UPDATE candidate_assignments
      SET file_number = NULLIF(regexp_replace(reference_number, '[^0-9]', '', 'g'), '')::bigint
      WHERE length(regexp_replace(reference_number, '[^0-9]', '', 'g')) BETWEEN 1 AND #{MAX_DIGITS}
    SQL
    stop_on_clashes!
    remove_index :candidate_assignments, name: 'index_candidate_assignments_on_reference_number'
    remove_column :candidate_assignments, :reference_number
    add_file_number_constraints
  end

  def down
    add_column :candidate_assignments, :reference_number, :string
    execute <<~SQL.squish
      UPDATE candidate_assignments SET reference_number = COALESCE(file_number::text, 'CA-' || id::text)
    SQL
    change_column_null :candidate_assignments, :reference_number, false
    add_index :candidate_assignments, :reference_number, unique: true,
                                                         name: 'index_candidate_assignments_on_reference_number'
    remove_check_constraint :candidate_assignments, name: 'candidate_assignments_file_number_positive'
    remove_column :candidate_assignments, :file_number
  end

  private

  def stop_on_clashes!
    clashes = select_rows(<<~SQL.squish)
      SELECT campaign_id, file_number FROM candidate_assignments
      WHERE file_number IS NOT NULL GROUP BY campaign_id, file_number HAVING COUNT(*) > 1
    SQL
    return if clashes.empty?

    raise ActiveRecord::MigrationError,
          "Same file number twice in one campaign (campaign_id, file_number): #{clashes.inspect}. " \
          'Change the reference numbers so their digits differ, then migrate again.'
  end

  # Unique within a campaign; assignments without a campaign are unique among themselves.
  def add_file_number_constraints
    add_index :candidate_assignments, %i[campaign_id file_number],
              unique: true, where: 'file_number IS NOT NULL AND campaign_id IS NOT NULL',
              name: 'index_candidate_assignments_on_campaign_file_number'
    add_index :candidate_assignments, :file_number,
              unique: true, where: 'file_number IS NOT NULL AND campaign_id IS NULL',
              name: 'index_candidate_assignments_on_file_number_no_campaign'
    add_check_constraint :candidate_assignments, 'file_number > 0', name: 'candidate_assignments_file_number_positive'
  end
end
