# frozen_string_literal: true

module DesconDeploy
  # Variables the production environment file must define, each either because
  # Rails refuses to boot without it (`ENV.fetch` with no default) or because
  # a silent default would point the application at the wrong place (a missing
  # DB_HOST means localhost, a missing AWS_REGION means us-east-1). Checked by
  # `deploy:check_env_file` before any release is built, by name only -- the
  # values are never read or printed.
  REQUIRED_ENV_NAMES = %w[
    ACTIVE_STORAGE_SERVICE
    AWS_REGION
    AWS_S3_BUCKET
    CORS_ALLOWED_ORIGINS
    DB_HOST
    DB_USERNAME
    DB_PASSWORD
    DB_NAME
    CACHE_DB_NAME
    QUEUE_DB_NAME
    CABLE_DB_NAME
    JWT_SECRET
    INVITATION_TOKEN_SECRET
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
  ].freeze
end
