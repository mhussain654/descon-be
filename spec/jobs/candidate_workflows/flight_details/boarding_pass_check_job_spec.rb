# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::FlightDetails::BoardingPassCheckJob do
  include ActiveJob::TestHelper

  before do
    ensure_canonical_workflow_stages!
    allow(DocumentOcr::TextractAdapter).to receive(:new).and_return(adapter)
  end

  let(:candidate) { create(:candidate, full_name: 'Sample Example Tester') }
  let(:detail) do
    create(:candidate_flight_detail, candidate_assignment: create(:candidate_assignment, candidate:),
                                     flight_number: 'QR-629', flight_departure_at: Time.utc(2026, 11, 20, 9, 0),
                                     boarding_pass_uploaded_at: Time.utc(2026, 11, 20, 4, 0),
                                     boarding_pass_check: 'pending').tap do |record|
      record.boarding_pass.attach(io: StringIO.new('photo'), filename: 'boarding-pass.jpg', content_type: 'image/jpeg')
    end
  end
  let(:upload_time) { detail.boarding_pass_uploaded_at.utc.iso8601(6) }
  let(:adapter) { instance_double(DocumentOcr::TextractAdapter) }
  let(:ocr_text) do
    { lines: ['TESTER/SAMPLE EXAMPLE', 'QR629', '20NOV', 'SEAT 12F'], answers: { 'NAME' => 'TESTER/SAMPLE' } }
  end

  around do |example|
    original = ENV.fetch('DOCUMENT_OCR_ENABLED', nil)
    ENV['DOCUMENT_OCR_ENABLED'] = 'true'
    example.run
    ENV['DOCUMENT_OCR_ENABLED'] = original
  end

  it 'records the result, the signals and the seat, and nothing of the text' do
    allow(adapter).to receive(:read_text).and_return(ocr_text)

    freeze_time { described_class.perform_now(detail.id, upload_time) }

    expect(adapter).to have_received(:read_text).with(bytes: 'photo', queries: described_class::QUERIES)
    expect(detail.reload).to have_attributes(boarding_pass_check: 'matched', boarding_pass_seat: '12F')
    expect(detail.boarding_pass_check_signals).to eq('flight_number' => true, 'date' => true, 'name' => true,
                                                     'seat' => true)
    expect(detail.boarding_pass_checked_at).to be_present
  end

  it 'does nothing for a photo that has since been replaced' do
    allow(adapter).to receive(:read_text).and_return(ocr_text)

    described_class.perform_now(detail.id, Time.utc(2026, 11, 19).iso8601(6))

    expect(adapter).not_to have_received(:read_text)
    expect(detail.reload.boarding_pass_check).to eq('pending')
  end

  it 'records the check as unavailable when OCR is off or cannot read the photo' do
    ENV['DOCUMENT_OCR_ENABLED'] = 'false'
    described_class.perform_now(detail.id, upload_time)
    expect(detail.reload.boarding_pass_check).to eq('unavailable')

    ENV['DOCUMENT_OCR_ENABLED'] = 'true'
    detail.update!(boarding_pass_check: 'pending')
    allow(adapter).to receive(:read_text).and_raise(DocumentOcr::PermanentError, 'unreadable')
    described_class.perform_now(detail.id, upload_time)
    expect(detail.reload.boarding_pass_check).to eq('unavailable')
  end

  it 'retries a passing provider failure and gives up as unavailable' do
    allow(adapter).to receive(:read_text).and_raise(DocumentOcr::TransientError, 'throttled')

    perform_enqueued_jobs { described_class.perform_later(detail.id, upload_time) }

    expect(adapter).to have_received(:read_text).exactly(3).times
    expect(detail.reload.boarding_pass_check).to eq('unavailable')
  end
end
