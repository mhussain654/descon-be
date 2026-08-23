# frozen_string_literal: true

module ImmutableRecord
  extend ActiveSupport::Concern

  included do
    before_update :raise_readonly_record
    before_destroy :raise_readonly_record
  end

  private

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} records are immutable"
  end
end
