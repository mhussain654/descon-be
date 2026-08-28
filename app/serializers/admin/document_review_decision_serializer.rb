# frozen_string_literal: true

module Admin
  class DocumentReviewDecisionSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        document: serialized_document,
        submission: serialized_submission
      }
    end

    private

    def serialized_document
      CandidateDocumentSerializer.new(@result.document.submission_item).as_json
    end

    def serialized_submission
      {
        id: @result.submission.public_id,
        review: DocumentReviewSummarySerializer.new(@result.summary).as_json
      }
    end
  end
end
