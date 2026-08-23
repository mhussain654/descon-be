# frozen_string_literal: true

require 'digest'

module Idempotency
  class ClaimLock
    def initialize(scope:, subject:, key:)
      @scope = scope
      @subject = subject
      @key = key
      @connection = IdempotencyKey.connection
      @held = false
    end

    def acquire
      @held = ActiveModel::Type::Boolean.new.cast(@connection.select_value(lock_sql))
    end

    def release
      return unless @held

      @connection.execute(unlock_sql)
      @held = false
    end

    private

    def lock_sql
      sql_for('SELECT pg_try_advisory_lock(?, ?)')
    end

    def unlock_sql
      sql_for('SELECT pg_advisory_unlock(?, ?)')
    end

    def sql_for(template)
      first_key, second_key = advisory_lock_keys
      ActiveRecord::Base.send(:sanitize_sql_array, [template, first_key, second_key])
    end

    def advisory_lock_keys
      digest = Digest::SHA256.hexdigest(
        "#{@scope}:#{@subject&.class&.name}:#{@subject&.id}:#{Digest::SHA256.hexdigest(@key)}"
      )

      [signed_32_bit_integer(digest[0, 8]), signed_32_bit_integer(digest[8, 8])]
    end

    def signed_32_bit_integer(hex_value)
      [hex_value].pack('H*').unpack1('l>')
    end
  end
end
