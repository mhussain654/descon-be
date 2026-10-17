# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentOcr::DateExtractor do
  let(:both) do
    { issued_on: Date.new(2021, 12, 6), expires_on: Date.new(2031, 12, 6),
      confidence_issued_on: 96.0, confidence_expires_on: 95.0 }
  end
  let(:issued_only) do
    { issued_on: Date.new(2021, 12, 6), expires_on: nil, confidence_issued_on: 96.0, confidence_expires_on: nil }
  end
  let(:expires_only) do
    { issued_on: nil, expires_on: Date.new(2031, 12, 6), confidence_issued_on: nil, confidence_expires_on: 94.0 }
  end
  let(:adapter) { instance_double(DocumentOcr::TextractAdapter) }

  def pdf_with_pages(count)
    Prawn::Document.new do |pdf|
      count.times do |index|
        index.zero? ? pdf.text('p1') : pdf.start_new_page && pdf.text('p')
      end
    end.render
  end

  def extract(sources) = described_class.call(sources:, adapter:)

  it 'returns the dates from the first file and stops there when both are found' do
    allow(adapter).to receive(:extract).and_return(both)
    downloaded = []
    sources = %w[front back].lazy.map { |name| (downloaded << name) && "image-#{name}".b }

    expect(extract(sources)).to eq(both)
    expect(downloaded).to eq(['front'])
    expect(adapter).to have_received(:extract).once
  end

  it 'falls back to the back image when the front gives no dates' do
    allow(adapter).to receive(:extract).with(bytes: 'front'.b).and_raise(DocumentOcr::PermanentError, 'none')
    allow(adapter).to receive(:extract).with(bytes: 'back'.b).and_return(both)

    expect(extract(['front'.b, 'back'.b])).to eq(both)
  end

  it 'merges a date found on each of two images' do
    allow(adapter).to receive(:extract).with(bytes: 'front'.b).and_return(issued_only)
    allow(adapter).to receive(:extract).with(bytes: 'back'.b).and_return(expires_only)

    expect(extract(['front'.b, 'back'.b])).to eq(
      issued_on: Date.new(2021, 12, 6), expires_on: Date.new(2031, 12, 6),
      confidence_issued_on: 96.0, confidence_expires_on: 94.0
    )
  end

  it 'reads each page of a two-page PDF as its own single-page document' do
    sent = []
    allow(adapter).to receive(:extract) do |bytes:|
      sent << CombinePDF.parse(bytes).pages.size
      sent.size == 1 ? raise(DocumentOcr::PermanentError, 'none') : both
    end

    expect(extract([pdf_with_pages(2)])).to eq(both)
    expect(sent).to eq([1, 1])
  end

  it 'never makes more than MAX_ATTEMPTS provider calls' do
    allow(adapter).to receive(:extract).and_raise(DocumentOcr::PermanentError, 'none')

    expect { extract(Array.new(6) { |index| "file-#{index}".b }) }.to raise_error(DocumentOcr::PermanentError, 'none')
    expect(adapter).to have_received(:extract).exactly(described_class::MAX_ATTEMPTS).times
  end

  it 'raises the provider error when nothing could be read anywhere' do
    allow(adapter).to receive(:extract).and_raise(DocumentOcr::PermanentError, 'unsupported')

    expect { extract(['a'.b]) }.to raise_error(DocumentOcr::PermanentError, 'unsupported')
  end

  it 'raises PermanentError when there are no files at all' do
    expect { extract([]) }.to raise_error(DocumentOcr::PermanentError, /no issue or expiry/)
  end

  it 'lets a retryable provider error escape so the job can retry' do
    allow(adapter).to receive(:extract).and_raise(DocumentOcr::TransientError, 'throttled')

    expect { extract(['a'.b]) }.to raise_error(DocumentOcr::TransientError)
  end
end
