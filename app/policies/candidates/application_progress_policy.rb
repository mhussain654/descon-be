# frozen_string_literal: true

module Candidates
  ApplicationProgressPolicy = Struct.new(:user, :record) do
    def show?
      user.present? && user.active_for_authentication? && user == record
    end
  end
end
