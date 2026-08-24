# frozen_string_literal: true

require 'digest'

module Database
  class AdvisoryTransactionLock < ApplicationService
    def initialize(scope:, key:, connection: ActiveRecord::Base.connection)
      @scope = scope
      @key = key
      @connection = connection
    end

    def call
      @connection.execute(lock_sql)
    end

    private

    def lock_sql
      first_key, second_key = advisory_lock_keys
      ActiveRecord::Base.send(:sanitize_sql_array, ['SELECT pg_advisory_xact_lock(?, ?)', first_key, second_key])
    end

    def advisory_lock_keys
      digest = Digest::SHA256.hexdigest("#{@scope}:#{Digest::SHA256.hexdigest(@key)}")
      [signed_32_bit_integer(digest[0, 8]), signed_32_bit_integer(digest[8, 8])]
    end

    def signed_32_bit_integer(hex_value)
      [hex_value].pack('H*').unpack1('l>')
    end
  end
end
