# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallOperationalSetting do
  describe '.current' do
    it 'creates the singleton row on first access' do
      expect { described_class.current }.to change(described_class, :count).from(0).to(1)
    end

    it 'returns the same row on subsequent access' do
      first_call = described_class.current

      expect(described_class.current).to eq(first_call)
    end

    it 'is race-safe against a concurrent first access' do
      described_class.current
      allow(described_class).to receive(:first).and_return(nil)

      expect { described_class.current }.not_to raise_error
      expect(described_class.count).to eq(1)
    end
  end

  it 'cannot be destroyed' do
    setting = described_class.current

    expect { setting.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'refuses a second row at the database level' do
    described_class.current

    expect { described_class.create!(singleton_guard: true) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'validates calling_hours_start/end within 0..23' do
    setting = described_class.current

    expect(setting.update(calling_hours_start: 24)).to be(false)
    expect(setting.update(calling_hours_end: -1)).to be(false)
    expect(setting.update(calling_hours_start: 0, calling_hours_end: 23)).to be(true)
  end

  it 'validates the numeric knobs are non-negative' do
    setting = described_class.current

    expect(setting.update(daily_outbound_call_limit: -1)).to be(false)
    expect(setting.update(daily_outbound_call_limit: 0)).to be(true)
  end

  it 'allows every knob to be nil (falls back to AiCalls::Configuration defaults)' do
    setting = described_class.current

    expect(setting).to be_valid
  end
end
