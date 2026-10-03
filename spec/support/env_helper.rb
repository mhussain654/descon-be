# frozen_string_literal: true

# Runs a block with ENV variables temporarily set (nil removes one), restoring
# the previous values afterwards.
module EnvHelper
  def with_env(values)
    originals = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| assign_env(key, value) }
    yield
  ensure
    originals&.each { |key, value| assign_env(key, value) }
  end

  private

  def assign_env(key, value)
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end

RSpec.configure { |config| config.include EnvHelper }
