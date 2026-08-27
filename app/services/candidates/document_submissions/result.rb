# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    Result = Data.define(:documents, :submission_id, :submission_state, :submitted_at)
  end
end
