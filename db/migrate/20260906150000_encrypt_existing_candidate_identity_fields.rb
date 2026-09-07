# frozen_string_literal: true

# Encrypts already-persisted plaintext cnic/next_of_kin_cnic/passport_number values now that
# Candidate declares `encrypts ..., deterministic: true` for all three (MPS-901). Unlike this
# repo's other data-backfill migrations, this one deliberately uses the live Candidate model
# (not a migration-scoped anonymous class) rather than raw SQL: Active Record Encryption's
# `encrypts` is what actually turns the plaintext into ciphertext on save, so there's no schema-
# level equivalent to fall back on. A plain re-save is enough -- no attribute values change,
# only how they're stored. Saved with validate: false: no field is actually changing here, and
# the model's own documented pre-existing mobile_number uniqueness collision in dev/test data
# (see Candidate's "No DB-level unique index yet" comment) would otherwise block this unrelated
# backfill on data quality this migration isn't the place to fix.
#
# The candidates_cnic_format/candidates_next_of_kin_cnic_format DB check constraints (added
# under MPS-102's schema, matching AGENTS.md's "use PostgreSQL constraints in addition to Rails
# validations") must go first: they regex-match the plaintext CNIC shape, and ciphertext can
# never match that shape, so every save (this backfill's included) would fail immediately
# otherwise. Rails' own `validates format:` on cnic/next_of_kin_cnic still runs before
# encryption (at `before_validation`/`validates`, against the plain in-memory value), so format
# correctness isn't actually lost here -- only the redundant DB-level copy of it, which
# encryption makes impossible to keep. passport_number never had a DB-level format constraint
# (Rails-level PASSPORT_NUMBER_FORMAT only), so there's nothing to drop for it.
class EncryptExistingCandidateIdentityFields < ActiveRecord::Migration[8.1]
  ENCRYPTED_ATTRIBUTES = %w[cnic next_of_kin_cnic passport_number].freeze

  def up
    remove_check_constraint :candidates, name: 'candidates_cnic_format'
    remove_check_constraint :candidates, name: 'candidates_next_of_kin_cnic_format'

    Candidate.unscoped.find_in_batches(batch_size: 500) do |batch|
      batch.each { |candidate| reencrypt!(candidate) }
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Cannot decrypt candidate identity fields back to plaintext automatically.'
  end

  private

  # Reassigning cnic = cnic is NOT enough: Rails' dirty-tracking compares the decrypted (cast)
  # value, and since it's identical, save! silently skips the UPDATE, leaving the row plaintext
  # forever -- confirmed empirically before landing this. Explicitly marking each attribute
  # changed forces the UPDATE (and therefore the encrypted re-serialization) to actually happen
  # regardless of the cast value's apparent equality.
  def reencrypt!(candidate)
    ENCRYPTED_ATTRIBUTES.each { |attribute| candidate.send(:attribute_will_change!, attribute) }
    candidate.save!(validate: false)
  end
end
