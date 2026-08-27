# frozen_string_literal: true

module Candidates
  DocumentSubmissionPolicy = Struct.new(:user, :record) do
    def create?
      user.present? && user.active_for_authentication? && user == record
    end
  end
end
