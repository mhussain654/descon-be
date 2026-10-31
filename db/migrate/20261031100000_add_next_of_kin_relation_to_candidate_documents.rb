# frozen_string_literal: true

# Client feedback on the document screens:
# - Next of Kin: the candidate says how their next of kin is related to them
#   when uploading the next of kin's CNIC, and a wife also needs a marriage
#   certificate. The relation is stored on that document version; the
#   marriage-certificate requirement row is flagged so the checklist offers it
#   only when the next of kin is the candidate's wife.
# - Every document is a scanned PDF: existing requirement rows (including any
#   project- or craft-specific ones the catalog seeder does not own) and the
#   column default stop accepting JPEG and PNG. Documents already uploaded are
#   kept as they are.
class AddNextOfKinRelationToCandidateDocuments < ActiveRecord::Migration[8.1]
  RELATIONS = %w[father mother brother wife son unmarried_sister unmarried_daughter].freeze
  IMAGE_AND_PDF = %w[application/pdf image/jpeg image/png].freeze
  PDF_ONLY = %w[application/pdf].freeze

  def up
    add_next_of_kin_relation
    change_table :document_requirements, bulk: true do |t|
      t.boolean :next_of_kin_spouse_only, null: false, default: false
      t.change_default :accepted_content_types, from: IMAGE_AND_PDF, to: PDF_ONLY
    end
    execute "UPDATE document_requirements SET accepted_content_types = '{application/pdf}', updated_at = NOW()"
  end

  # Rows switched to PDF only stay that way: which ones accepted images before is not recorded.
  def down
    change_table :document_requirements, bulk: true do |t|
      t.change_default :accepted_content_types, from: PDF_ONLY, to: IMAGE_AND_PDF
      t.remove :next_of_kin_spouse_only
    end
    remove_check_constraint :candidate_documents, name: 'candidate_documents_next_of_kin_relation_known'
    remove_column :candidate_documents, :next_of_kin_relation
  end

  private

  def add_next_of_kin_relation
    known = RELATIONS.map { |relation| connection.quote(relation) }.join(', ')
    add_column :candidate_documents, :next_of_kin_relation, :string
    add_check_constraint :candidate_documents, "next_of_kin_relation IS NULL OR next_of_kin_relation IN (#{known})",
                         name: 'candidate_documents_next_of_kin_relation_known'
  end
end
