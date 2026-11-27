# frozen_string_literal: true

# The file number becomes the registration number, named as in KuickPay's
# portal and CSV: the client's own number for a candidate, unique across the
# whole organisation (they use it in another system and on KuickPay's portal
# too), and sent to KuickPay as the voucher's registration number, so the
# candidate's Kuickpay ID is the institution code + this number. Stops,
# changing nothing, if two candidates already share a number.
class RenameFileNumberToRegistrationNumber < ActiveRecord::Migration[8.1]
  def up
    stop_on_shared_numbers!
    remove_index :candidate_assignments, name: 'index_candidate_assignments_on_campaign_file_number'
    remove_index :candidate_assignments, name: 'index_candidate_assignments_on_file_number_no_campaign'
    remove_check_constraint :candidate_assignments, name: 'candidate_assignments_file_number_positive'
    rename_column :candidate_assignments, :file_number, :registration_number
    add_index :candidate_assignments, :registration_number,
              unique: true, where: 'registration_number IS NOT NULL',
              name: 'index_candidate_assignments_on_registration_number'
    add_check_constraint :candidate_assignments, 'registration_number > 0',
                         name: 'candidate_assignments_registration_number_positive'
  end

  def down
    remove_check_constraint :candidate_assignments, name: 'candidate_assignments_registration_number_positive'
    remove_index :candidate_assignments, name: 'index_candidate_assignments_on_registration_number'
    rename_column :candidate_assignments, :registration_number, :file_number
    add_index :candidate_assignments, %i[campaign_id file_number],
              unique: true, where: 'file_number IS NOT NULL AND campaign_id IS NOT NULL',
              name: 'index_candidate_assignments_on_campaign_file_number'
    add_index :candidate_assignments, :file_number,
              unique: true, where: 'file_number IS NOT NULL AND campaign_id IS NULL',
              name: 'index_candidate_assignments_on_file_number_no_campaign'
    add_check_constraint :candidate_assignments, 'file_number > 0', name: 'candidate_assignments_file_number_positive'
  end

  private

  def stop_on_shared_numbers!
    shared = select_values(<<~SQL.squish)
      SELECT file_number FROM candidate_assignments
      WHERE file_number IS NOT NULL GROUP BY file_number HAVING COUNT(*) > 1
    SQL
    return if shared.empty?

    raise ActiveRecord::MigrationError,
          "These file numbers belong to more than one candidate: #{shared.join(', ')}. " \
          'Give each candidate their own number, then migrate again.'
  end
end
