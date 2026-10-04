# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::FileSetValidator do
  def requirement(profile)
    DocumentRequirement.new(
      { accepted_content_types: DocumentChecklists::Definitions::CONTENT_TYPES, maximum_file_size: 5.megabytes }
        .merge(DocumentChecklists::Definitions::UPLOAD_PROFILES.fetch(profile))
    )
  end

  def entry(side_code, content_type: 'image/jpeg', byte_size: 1024)
    details = Candidates::Documents::UploadedFileDetails.new(filename: 'f', content_type:, byte_size:,
                                                             checksum_sha256: 'a' * 64)
    { details:, side_code: }
  end

  def reason_for(profile, entries)
    described_class.call(requirement: requirement(profile), entries:)
    nil
  rescue InvalidDocumentFilesError => e
    e.details.fetch(:reason)
  end

  describe 'passport (one combined PDF or page 1 + page 2 images)' do
    it 'accepts one combined PDF' do
      expect(reason_for(:two_pages, [entry('combined', content_type: 'application/pdf')])).to be_nil
    end

    it 'accepts two images labelled page 1 and page 2' do
      expect(reason_for(:two_pages, [entry('page_1'), entry('page_2')])).to be_nil
    end

    it 'rejects a lone page, a combined image, and a combined PDF with extra files' do
      expect(reason_for(:two_pages, [entry('page_1')])).to eq('incomplete_side_pair')
      expect(reason_for(:two_pages, [entry('combined')])).to eq('combined_requires_pdf')
      expect(reason_for(:two_pages, [entry('combined', content_type: 'application/pdf'), entry('page_1')]))
        .to eq('combined_must_be_alone')
    end
  end

  describe 'CNIC (front and back)' do
    it 'accepts front + back images' do
      expect(reason_for(:two_sided, [entry('front'), entry('back')])).to be_nil
    end

    it 'requires both sides, unique labels and known labels' do
      expect(reason_for(:two_sided, [entry('front')])).to eq('incomplete_side_pair')
      expect(reason_for(:two_sided, [entry('front'), entry('front')])).to eq('duplicate_side_code')
      expect(reason_for(:two_sided, [entry('page_1'), entry('page_2')])).to eq('side_code_not_allowed')
      expect(reason_for(:two_sided, [entry(nil), entry('back')])).to eq('side_code_required')
    end

    it 'enforces the file count' do
      expect(reason_for(:two_sided, [])).to eq('too_few_files')
      expect(reason_for(:two_sided, [entry('front'), entry('back'), entry('front')])).to eq('too_many_files')
    end
  end

  it 'accepts several certificates under one requirement' do
    expect(reason_for(:certificates, Array.new(3) { entry('certificate', content_type: 'application/pdf') })).to be_nil
  end

  it 'rejects side labels on a single-file document' do
    expect(reason_for(:single, [entry('front')])).to eq('side_code_not_allowed')
  end

  it "rejects a file type or size outside the requirement's rules, by field" do
    expect do
      described_class.call(requirement: requirement(:photo), entries: [entry(nil, content_type: 'application/pdf')])
    end
      .to raise_error(UnsupportedFileTypeError) { |error|
            expect(error.field).to eq('candidate_document.files[0].file')
          }
    expect { described_class.call(requirement: requirement(:single), entries: [entry(nil, byte_size: 6.megabytes)]) }
      .to raise_error(FileTooLargeError)
  end
end
