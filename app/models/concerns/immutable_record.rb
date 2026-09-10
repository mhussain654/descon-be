# frozen_string_literal: true

# Concern that makes a model append-only: once created, records can never be updated or
# destroyed, which suits audit-style records like payment events.
module ImmutableRecord
  extend ActiveSupport::Concern

  included do
    before_update :raise_readonly_record
    before_destroy :raise_readonly_record
  end

  private

  # Blocks any update or destroy attempt by raising, since these records must never change.
  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} records are immutable"
  end
end
