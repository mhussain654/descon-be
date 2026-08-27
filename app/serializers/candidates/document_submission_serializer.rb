# frozen_string_literal: true

module Candidates
  class DocumentSubmissionSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        message: I18n.t('api.candidate_document_submissions.submitted'),
        submission_id: @result.submission_id,
        submitted_at: @result.submitted_at,
        submission_state: @result.submission_state,
        documents: @result.documents
      }
    end
  end
end
