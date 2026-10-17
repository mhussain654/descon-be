# frozen_string_literal: true

require 'combine_pdf'

module DocumentOcr
  # Textract's synchronous calls accept only ONE page per PDF. A candidate may
  # upload a CNIC or passport as a multi-page PDF (front and back, or a scan
  # with extra pages), so this returns the first MAX_PAGES pages as separate
  # single-page documents for the adapter to try in order. Images, one-page
  # PDFs and anything that cannot be parsed are returned unchanged -- Textract
  # then accepts or rejects them itself.
  #
  # Usage: DocumentOcr::PdfPageSplitter.call(bytes:) -> [String]
  class PdfPageSplitter < ApplicationService
    MAX_PAGES = 2
    PDF_HEADER = '%PDF'

    def initialize(bytes:)
      @bytes = bytes
    end

    def call
      return [@bytes] unless @bytes.to_s.b.start_with?(PDF_HEADER)

      pages = CombinePDF.parse(@bytes).pages
      return [@bytes] if pages.size <= 1

      pages.first(MAX_PAGES).map { |page| single_page_pdf(page) }
    rescue CombinePDF::ParsingError, CombinePDF::EncryptionError
      [@bytes]
    end

    private

    def single_page_pdf(page)
      document = CombinePDF.new
      document << page
      document.to_pdf
    end
  end
end
