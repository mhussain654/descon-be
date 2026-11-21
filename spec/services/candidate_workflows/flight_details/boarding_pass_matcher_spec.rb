# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::FlightDetails::BoardingPassMatcher do
  # Made-up passenger and flight; the layout follows a typical printed boarding pass.
  let(:boarding_pass_lines) do
    ['BOARDING PASS', 'NAME OF PASSENGER', 'TESTER/SAMPLE EXAMPLE MR', 'FROM LAHORE TO DOHA',
     'FLIGHT QR 0629', 'DATE 20NOV', 'GATE A4 BOARDING 01:15', 'SEAT', '23A']
  end

  def match(lines: boarding_pass_lines, answers: {}, flight_number: 'QR-629', flight_day: Date.new(2026, 11, 20),
            full_name: 'Sample Example Tester')
    described_class.call(lines:, answers:, flight_number:, flight_day:, full_name:)
  end

  it 'matches a boarding pass for the booked flight, and reads the seat' do
    expect(match).to eq(check: 'matched', seat: '23A',
                        signals: { flight_number: true, date: true, name: true, seat: true })
  end

  it 'prefers the seat OCR answered, and accepts a seat given at the gate' do
    expect(match(answers: { 'SEAT' => '07C' })[:seat]).to eq('7C')
    expect(match(lines: boarding_pass_lines - ['23A'], answers: { 'SEAT' => 'GATE' })[:seat]).to eq('GATE')
  end

  it 'does not need a seat' do
    result = match(lines: boarding_pass_lines - %w[SEAT 23A])

    expect(result[:check]).to eq('matched')
    expect(result[:signals][:seat]).to be(false)
    expect(result[:seat]).to be_nil
  end

  it 'reads the date in other printed forms' do
    ['20 NOV 2026', 'NOV 20', '20/11/2026', '20.11.26', '2026-11-20', '20NOV26'].each do |printed|
      lines = boarding_pass_lines.map { |line| line == 'DATE 20NOV' ? "DATE #{printed}" : line }
      expect(match(lines:)[:signals][:date]).to be(true), printed
    end
  end

  it 'does not take another day or flight for this one' do
    other_day = boarding_pass_lines.map { |line| line == 'DATE 20NOV' ? 'DATE 21NOV' : line }
    expect(match(lines: other_day)[:signals][:date]).to be(false)
    expect(match(flight_number: 'QR-62')[:signals][:flight_number]).to be(false)
    expect(match(flight_number: 'EK-629')[:signals][:flight_number]).to be(false)
  end

  it 'asks staff to look when the name does not match or only part of the flight matches' do
    expect(match(full_name: 'Other Person Entirely')[:check]).to eq('needs_review')
    expect(match(flight_day: Date.new(2026, 12, 3))[:check]).to eq('needs_review')
  end

  it 'flags a photo that shows neither the flight number nor the date' do
    expect(match(lines: ['GROCERY RECEIPT', 'TOTAL 450'])).to include(check: 'not_boarding_pass', seat: nil)
  end

  it 'matches a flight number recorded without a two-letter airline code' do
    lines = boarding_pass_lines.map { |line| line == 'FLIGHT QR 0629' ? 'FLIGHT 9P842' : line }
    expect(match(lines:, flight_number: '9P842')[:signals][:flight_number]).to be(true)
    expect(match(lines:, flight_number: 'XYZ1')[:signals][:flight_number]).to be(false)
  end
end
