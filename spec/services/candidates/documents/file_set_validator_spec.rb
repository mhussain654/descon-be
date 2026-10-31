# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::FileSetValidator do
  # A requirement shaped like one of the approved catalog's upload profiles.
  def catalog_requirement(profile)
    DocumentRequirement.new(
      { accepted_content_types: DocumentChecklists::Definitions::CONTENT_TYPES, maximum_file_size: 5.megabytes }
        .merge(DocumentChecklists::Definitions::UPLOAD_PROFILES.fetch(profile))
    )
  end

  # A requirement that still allows separate sides as images -- the validator
  # supports any requirement's rules, not only the current catalog's.
  def two_sided_image_requirement
    DocumentRequirement.new(
      accepted_content_types: %w[application/pdf image/jpeg], maximum_file_size: 5.megabytes, minimum_files: 1,
      maximum_files: 2, combined_pdf_allowed: true, allowed_side_codes: %w[combined front back]
    )
  end

  def entry(side_code, content_type: 'application/pdf', byte_size: 1024)
    details = Candidates::Documents::UploadedFileDetails.new(filename: 'f', content_type:, byte_size:,
                                                             checksum_sha256: 'a' * 64)
    { details:, side_code: }
  end

  def reason_for(requirement, entries)
    described_class.call(requirement:, entries:)
    nil
  rescue InvalidDocumentFilesError => e
    e.details.fetch(:reason)
  end

  describe 'the approved catalog (scanned PDFs only)' do
    it 'accepts a passport or CNIC as one combined PDF' do
      expect(reason_for(catalog_requirement(:two_pages), [entry('combined')])).to be_nil
      expect(reason_for(catalog_requirement(:two_sided), [entry('combined')])).to be_nil
    end

    it 'does not accept separate pages or sides any more' do
      expect(reason_for(catalog_requirement(:two_pages), [entry('page_1'), entry('page_2')])).to eq('too_many_files')
      expect(reason_for(catalog_requirement(:two_sided), [entry('front')])).to eq('side_code_not_allowed')
    end

    it 'rejects a JPEG or PNG for every kind of document, the photograph included' do
      side_codes = { two_pages: 'combined', two_sided: 'combined', certificates: 'certificate' }
      %i[single photo two_pages two_sided certificates].each do |profile|
        side_code = side_codes[profile]
        expect do
          described_class.call(requirement: catalog_requirement(profile),
                               entries: [entry(side_code, content_type: 'image/jpeg')])
        end
          .to raise_error(UnsupportedFileTypeError) { |error|
                expect(error.field).to eq('candidate_document.files[0].file')
              }
      end
    end

    it 'accepts several certificate PDFs under one requirement' do
      expect(reason_for(catalog_requirement(:certificates), Array.new(3) { entry('certificate') })).to be_nil
    end

    it 'rejects side labels on a single-file document, and a file over the size limit' do
      expect(reason_for(catalog_requirement(:single), [entry('front')])).to eq('side_code_not_allowed')
      expect do
        described_class.call(requirement: catalog_requirement(:single), entries: [entry(nil, byte_size: 6.megabytes)])
      end
        .to raise_error(FileTooLargeError)
    end
  end

  describe 'a requirement that allows separate sides' do
    it 'accepts front + back, or one combined PDF' do
      expect(reason_for(two_sided_image_requirement,
                        [entry('front', content_type: 'image/jpeg'), entry('back')])).to be_nil
      expect(reason_for(two_sided_image_requirement, [entry('combined')])).to be_nil
    end

    it 'requires both sides, unique labels and known labels' do
      requirement = two_sided_image_requirement
      expect(reason_for(requirement, [entry('front')])).to eq('incomplete_side_pair')
      expect(reason_for(requirement, [entry('front'), entry('front')])).to eq('duplicate_side_code')
      expect(reason_for(requirement, [entry('page_1'), entry('page_2')])).to eq('side_code_not_allowed')
      expect(reason_for(requirement, [entry(nil), entry('back')])).to eq('side_code_required')
    end

    it 'rejects a combined image and a combined PDF with extra files' do
      requirement = two_sided_image_requirement
      expect(reason_for(requirement, [entry('combined', content_type: 'image/jpeg')])).to eq('combined_requires_pdf')
      expect(reason_for(requirement, [entry('combined'), entry('front')])).to eq('combined_must_be_alone')
    end

    it 'enforces the file count' do
      expect(reason_for(two_sided_image_requirement, [])).to eq('too_few_files')
      expect(reason_for(two_sided_image_requirement, [entry('front'), entry('back'), entry('front')]))
        .to eq('too_many_files')
    end
  end
end
