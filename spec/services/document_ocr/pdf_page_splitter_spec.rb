# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentOcr::PdfPageSplitter do
  def pdf_with_pages(count)
    Prawn::Document.new do |pdf|
      count.times do |index|
        pdf.start_new_page if index.positive?
        pdf.text "Page #{index + 1}"
      end
    end.render
  end

  def page_count(bytes) = CombinePDF.parse(bytes).pages.size

  it 'returns an image unchanged' do
    png = "\x89PNG\r\n\x1A\n-image-".b

    expect(described_class.call(bytes: png)).to eq([png])
  end

  it 'returns a one-page PDF unchanged' do
    pdf = pdf_with_pages(1)

    expect(described_class.call(bytes: pdf)).to eq([pdf])
  end

  it 'splits a two-page PDF into two single-page PDFs' do
    pages = described_class.call(bytes: pdf_with_pages(2))

    expect(pages.size).to eq(2)
    expect(pages.map { |page| page_count(page) }).to eq([1, 1])
  end

  it 'keeps only the first pages of a long PDF, in order' do
    pages = described_class.call(bytes: pdf_with_pages(5))

    expect(pages.size).to eq(described_class::MAX_PAGES)
    expect(pages.map { |page| CombinePDF.parse(page).pages.first.to_s }).to all(be_present)
  end

  it 'returns the original bytes when the PDF cannot be parsed' do
    broken = '%PDF-1.4 this is not really a pdf'

    expect(described_class.call(bytes: broken)).to eq([broken])
  end
end
