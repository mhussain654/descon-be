# frozen_string_literal: true

Rails.application.configure do
  non_production_defaults = {
    primary_key: 'a' * 32,
    deterministic_key: 'b' * 32,
    key_derivation_salt: 'c' * 32
  }

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

  config.active_record.encryption.primary_key = encryption_config.fetch(:primary_key)
  config.active_record.encryption.deterministic_key = encryption_config.fetch(:deterministic_key)
  config.active_record.encryption.key_derivation_salt = encryption_config.fetch(:key_derivation_salt)
end
