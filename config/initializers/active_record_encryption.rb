# frozen_string_literal: true

non_production_defaults = {
  primary_key: 'a' * 32,
  deterministic_key: 'b' * 32,
  key_derivation_salt: 'c' * 32
}.freeze

encryption_config = if Rails.env.production?
                      {
                        primary_key: ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'),
                        deterministic_key: ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY'),
                        key_derivation_salt: ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT')
                      }
                    else
                      {
                        primary_key: ENV.fetch(
                          'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY',
                          non_production_defaults[:primary_key]
                        ),
                        deterministic_key: ENV.fetch(
                          'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY',
                          non_production_defaults[:deterministic_key]
                        ),
                        key_derivation_salt: ENV.fetch(
                          'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT',
                          non_production_defaults[:key_derivation_salt]
                        )
                      }
                    end

Rails.application.config.active_record.encryption.primary_key = encryption_config.fetch(:primary_key)
Rails.application.config.active_record.encryption.deterministic_key = encryption_config.fetch(:deterministic_key)
Rails.application.config.active_record.encryption.key_derivation_salt = encryption_config.fetch(:key_derivation_salt)

# Required for the MPS-901 candidate cnic/next_of_kin_cnic/passport_number rollout: without
# this, reading any row written before `encrypts` was declared on those columns raises
# ActiveRecord::Encryption::Errors::Decryption (Rails treats every stored value as ciphertext
# once a column is declared encrypted). With it, a value that isn't valid ciphertext is
# returned as-is instead of raising -- letting EncryptExistingCandidateIdentityFields's re-save
# backfill (and any row created in the brief window before that migration runs) read the old
# plaintext safely and encrypt it on write, and letting any deploy that skips the backfill fail
# safe (readable, not a 500) rather than fail hard.
#
# This is a *migration-window* setting, not a permanent one -- security review finding: leaving
# it enabled indefinitely hides an incomplete rollout and lets legacy plaintext go unnoticed
# forever. Exit plan:
#   1. Deploy this initializer + the EncryptExistingCandidateIdentityFields backfill migration.
#   2. Run `bin/rails encryption:verify_candidate_identity_plaintext` (below) against production
#      and confirm it reports zero remaining plaintext rows.
#   3. Ship a follow-up deploy that removes the ENV override (or sets
#      ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED_DATA=false) once step 2 is clean -- tracked
#      as a required follow-up, not optional cleanup.
# Kept ENV-overridable (defaulting to enabled) specifically so that follow-up deploy is a config
# change, not a code change.
Rails.application.config.active_record.encryption.support_unencrypted_data =
  ActiveModel::Type::Boolean.new.cast(ENV.fetch('ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED_DATA', 'true'))

# Fails fast at boot rather than on the first request that happens to touch an encrypted
# column: Active Record Encryption silently accepts a key of any length, but its underlying
# AES-256-GCM cipher requires each key to be at least 32 bytes, and will raise deep inside
# encryption/decryption (a confusing place to first discover a misconfigured key) if it is not.
%i[primary_key deterministic_key key_derivation_salt].each do |key_name|
  key_value = encryption_config.fetch(key_name)
  next if key_value.to_s.bytesize >= 32

  raise "config.active_record.encryption.#{key_name} must be at least 32 bytes " \
        "(got #{key_value.to_s.bytesize}) -- refusing to boot with a weak encryption key."
end
