# frozen_string_literal: true

module Admin
  class DocumentReviewQueueItemSerializer
    def initialize(submission)
      @submission = submission
    end

    def as_json(*)
      {
        id: @submission.public_id,
        candidate: serialized_candidate,
        assignment: serialized_assignment,
        submitted_at: @submission.submitted_at.utc.iso8601,
        review: DocumentReviewSummarySerializer.new(review_summary).as_json
      }
    end

    private

    def review_summary
      @review_summary ||= DocumentReviews::SubmissionSummaryBuilder.call(submission: @submission)
    end

    def serialized_assignment
      assignment = @submission.candidate_assignment

      {
        id: assignment.public_id,
        reference_number: assignment.reference_number,
        country: serialized_reference_record(assignment.country),
        project: serialized_reference_record(assignment.project),
        craft: serialized_reference_record(assignment.craft)
      }
    end

    def serialized_candidate
      candidate = @submission.candidate_assignment.candidate

      {
        id: candidate.public_id,
        full_name: candidate.full_name
      }
    end

    def serialized_reference_record(record)
      {
        code: record.code,
        name: record.name_for
      }
    end
  end
end
