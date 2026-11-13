# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalAppointmentSetting do
  before { described_class.delete_all }

  it 'is a single row, created blank on first access' do
    setting = described_class.current

    expect(described_class.current).to eq(setting)
    expect(setting).to have_attributes(center_name: nil, center_address: nil, appointment_on: nil,
                                       appointment_time: nil)
    expect { setting.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'tidies what staff typed and leaves blank values unset' do
    setting = described_class.current
    setting.update!(center_name: '  Al Shifa   Medical Centre ', center_address: ' ', appointment_time: '')

    expect(setting).to have_attributes(center_name: 'Al Shifa Medical Centre', center_address: nil,
                                       appointment_time: nil)
  end

  it 'accepts only a 24-hour HH:MM time' do
    setting = described_class.current

    expect(setting.update(appointment_time: '09:30')).to be(true)
    expect(setting.update(appointment_time: '9:30')).to be(false)
    expect(setting.update(appointment_time: '24:00')).to be(false)
  end

  it 'gives its set values as the medical appointment evidence defaults' do
    setting = described_class.current
    setting.update!(center_name: 'Al Shifa Medical Centre', appointment_on: Date.new(2026, 11, 20))

    expect(setting.evidence_defaults).to eq('medical_center_name' => 'Al Shifa Medical Centre',
                                            'medical_appointment_date' => '2026-11-20')
  end
end
