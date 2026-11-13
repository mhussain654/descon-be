# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FlightDetailSetting do
  before { described_class.delete_all }

  it 'is a single row, created blank on first access' do
    setting = described_class.current

    expect(described_class.current).to eq(setting)
    expect(setting).to have_attributes(airline: nil, flight_number: nil, sector: nil, departure_on: nil,
                                       departure_time: nil)
    expect { setting.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'tidies what staff typed and leaves blank values unset' do
    setting = described_class.current
    setting.update!(airline: '  Qatar   Airways ', flight_number: ' ', sector: ' LHE-DOH ')

    expect(setting).to have_attributes(airline: 'Qatar Airways', flight_number: nil, sector: 'LHE-DOH')
  end

  it 'accepts only a 24-hour HH:MM time, given together with the date' do
    setting = described_class.current

    expect(setting.update(departure_on: Date.new(2026, 11, 20), departure_time: '14:30')).to be(true)
    expect(setting.update(departure_time: '2:30 pm')).to be(false)
    expect(setting.reload.update(departure_time: nil)).to be(false)
    expect(setting.reload.update(departure_on: nil)).to be(false)
  end

  it 'gives its set values as the flight evidence defaults, the departure as a local date and time' do
    setting = described_class.current
    setting.update!(airline: 'Qatar Airways', sector: 'LHE-DOH', departure_on: Date.new(2026, 11, 20),
                    departure_time: '14:30')

    expect(setting.evidence_defaults).to eq('airline' => 'Qatar Airways', 'sector' => 'LHE-DOH',
                                            'flight_date' => '2026-11-20T14:30')
  end
end
