# frozen_string_literal: true

class BackfillCandidateDocumentSubmissionItems < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class Submission < ApplicationRecord
    self.table_name = 'candidate_document_submissions'

    belongs_to :candidate_assignment, class_name: 'BackfillCandidateDocumentSubmissionItems::Assignment'
    has_many :submission_items, class_name: 'BackfillCandidateDocumentSubmissionItems::SubmissionItem',
                                foreign_key: :candidate_document_submission_id, dependent: :delete_all
  end

  class SubmissionItem < ApplicationRecord
    self.table_name = 'candidate_document_submission_items'
  end

  class Assignment < ApplicationRecord
    self.table_name = 'candidate_assignments'

    has_many :candidate_documents, class_name: 'BackfillCandidateDocumentSubmissionItems::Document'
  end

  class Document < ApplicationRecord
    self.table_name = 'candidate_documents'

    belongs_to :document_type, class_name: 'BackfillCandidateDocumentSubmissionItems::DocumentType'
  end

  class DocumentType < ApplicationRecord
    self.table_name = 'document_types'
  end

  class DocumentRequirement < ApplicationRecord
    self.table_name = 'document_requirements'

    belongs_to :document_type, class_name: 'BackfillCandidateDocumentSubmissionItems::DocumentType'
  end

  def up
    Submission.includes(candidate_assignment: { candidate_documents: :document_type }).find_each do |submission|
      next if submission.submission_items.exists?

      backfill_submission_items!(submission)
    end
  end

  def down; end

  private

  def backfill_submission_items!(submission)
    assignment = submission.candidate_assignment
    requirements_by_document_type_id = resolved_requirements_by_document_type_id(assignment)
    rows = submission_item_rows(submission, assignment, requirements_by_document_type_id)

    return if rows.empty?

    SubmissionItem.transaction(requires_new: true) do
      rows.each { |attributes| SubmissionItem.create!(attributes) }
    end
  end

  def submission_item_rows(submission, assignment, requirements_by_document_type_id)
    assignment.candidate_documents.where(superseded_at: nil).includes(:document_type).filter_map do |document|
      submission_item_attributes(submission, document, requirements_by_document_type_id[document.document_type_id])
    end
  end

  def submission_item_attributes(submission, document, requirement)
    return unless requirement

    {
      candidate_document_submission_id: submission.id,
      candidate_document_id: document.id,
      requirement_code: requirement.document_type.code,
      required: requirement.required,
      created_at: submission.created_at,
      updated_at: submission.updated_at
    }
  end

  def resolved_requirements_by_document_type_id(assignment)
    applicable_requirements(assignment)
      .group_by(&:document_type_id)
      .transform_values { |requirements| prioritize_requirement(requirements) }
  end

  def applicable_requirements(assignment)
    DocumentRequirement
      .includes(:document_type)
      .where(active: true)
      .where(country_id: [nil, assignment.country_id])
      .where(project_id: [nil, assignment.project_id])
      .where(craft_id: [nil, assignment.craft_id])
      .to_a
  end

  def prioritize_requirement(requirements)
    requirements.max_by do |requirement|
      [specificity_score(requirement), requirement.required ? 1 : 0, -requirement.id]
    end
  end

  def specificity_score(requirement)
    [requirement.country_id, requirement.project_id, requirement.craft_id].count(&:present?)
  end
end
