# frozen_string_literal: true

# Candidate already declares `validates :mobile_number, uniqueness: true`
# (app/models/candidate.rb), but nothing at the database level actually
# enforces it -- a real gap on its own (AGENTS.md: "Use PostgreSQL
# constraints in addition to Rails validations for invariants"), and newly
# consequential now that inbound AI-call caller-ID lookup
# (`Candidate.active.find_by(mobile_number:)`) treats this column as a
# unique key for identifying who is calling. See
# BackfillCandidateMobileNumbersToE164, which normalizes existing values
# into the same format this index now protects.
#
# Refuses to run (with a clear, actionable error naming the duplicates)
# rather than let `add_index` fail with an opaque Postgres error, or -- far
# worse -- silently succeed against a table that happens to have no
# duplicates in this environment while leaving a genuinely duplicated
# production dataset for someone else to discover later. Resolving which of
# two duplicate candidate rows is canonical is a consequential data decision
# this migration does not make unilaterally.
class AddUniqueIndexToCandidatesMobileNumber < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  OLD_INDEX_NAME = 'index_candidates_on_mobile_number'
  NEW_INDEX_NAME = 'index_candidates_on_mobile_number_unique'

  class MigrationCandidate < ApplicationRecord
    self.table_name = 'candidates'
  end

  def up
    refuse_if_duplicates_exist!

    # Replaces, rather than adds alongside, the existing plain index -- a
    # unique index already serves the same equality-lookup access pattern,
    # so keeping both would just be redundant write overhead.
    add_index :candidates, :mobile_number, unique: true, algorithm: :concurrently, name: NEW_INDEX_NAME
    remove_index :candidates, name: OLD_INDEX_NAME, algorithm: :concurrently
  end

  def down
    add_index :candidates, :mobile_number, algorithm: :concurrently, name: OLD_INDEX_NAME
    remove_index :candidates, name: NEW_INDEX_NAME, algorithm: :concurrently
  end

  private

  def refuse_if_duplicates_exist!
    duplicated_numbers = duplicated_mobile_numbers
    return if duplicated_numbers.empty?

    ids_by_number = duplicated_numbers.index_with { |number| MigrationCandidate.where(mobile_number: number).ids }
    raise ActiveRecord::MigrationError,
          "Refusing to add a unique index on candidates.mobile_number: duplicate values exist -- #{ids_by_number}. " \
          'Resolve these duplicates (merge or update the affected candidate rows) before re-running this migration.'
  end

  def duplicated_mobile_numbers
    MigrationCandidate.group(:mobile_number).having('count(*) > 1').count.keys
  end
end
