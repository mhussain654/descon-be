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
Rails.application.config.active_record.encryption.support_unencrypted_data = true
