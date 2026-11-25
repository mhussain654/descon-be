# frozen_string_literal: true

# Candidates may upload each document as a scanned PDF or as photos again
# (photos at least 500 x 500 pixels, checked on upload). Reverses the
# PDF-only switch in 20261031100000:
# - every requirement row, and the column default, accept PDF, JPEG and PNG;
# - two-page/two-sided documents still set to one combined PDF take a photo
#   of each page/side too (page 1/page 2 for the passport, front/back for the
#   CNICs and the driving licence);
# - the catalog's own rows get the updated instructions, which mention photos.
# Documents already uploaded are kept as they are.
class AllowDocumentPhotosAgain < ActiveRecord::Migration[8.1]
  IMAGE_AND_PDF = %w[application/pdf image/jpeg image/png].freeze
  PDF_ONLY = %w[application/pdf].freeze
  PAIR_SIDE_CODES = {
    'passport' => %w[combined page_1 page_2],
    'cnic' => %w[combined front back],
    'next_of_kin_cnic' => %w[combined front back],
    'qatar_driving_licence' => %w[combined front back]
  }.freeze

  def up
    change_column_default :document_requirements, :accepted_content_types, from: PDF_ONLY, to: IMAGE_AND_PDF
    execute "UPDATE document_requirements SET accepted_content_types = #{array(IMAGE_AND_PDF)}, updated_at = NOW()"
    PAIR_SIDE_CODES.each do |code, side_codes|
      update_rows(code, "allowed_side_codes = #{array(side_codes)}, maximum_files = 2",
                  "allowed_side_codes = #{array(%w[combined])}")
    end
    update_instructions
  end

  # Instructions keep their photo wording: the PDF-only text is not recorded here.
  def down
    change_column_default :document_requirements, :accepted_content_types, from: IMAGE_AND_PDF, to: PDF_ONLY
    execute "UPDATE document_requirements SET accepted_content_types = #{array(PDF_ONLY)}, updated_at = NOW()"
    PAIR_SIDE_CODES.each do |code, side_codes|
      update_rows(code, "allowed_side_codes = #{array(%w[combined])}, maximum_files = 1",
                  "allowed_side_codes = #{array(side_codes)}")
    end
  end

  private

  def update_rows(code, assignments, condition)
    execute <<~SQL.squish
      UPDATE document_requirements SET #{assignments}, updated_at = NOW()
      WHERE #{condition}
        AND document_type_id IN (SELECT id FROM document_types WHERE code = #{connection.quote(code)})
    SQL
  end

  def update_instructions
    DocumentChecklists::Instructions::TEXT.each do |code, (english, urdu)|
      execute <<~SQL.squish
        UPDATE document_requirements
        SET instructions_en = #{connection.quote(english)}, instructions_ur = #{connection.quote(urdu)},
            updated_at = NOW()
        WHERE project_id IS NULL AND craft_id IS NULL
          AND document_type_id IN (SELECT id FROM document_types WHERE code = #{connection.quote(code)})
      SQL
    end
  end

  def array(values)
    connection.quote("{#{values.join(',')}}")
  end
end
