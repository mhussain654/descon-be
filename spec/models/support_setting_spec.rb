# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SupportSetting do
  # db:seed creates this singleton for real against a freshly prepared test
  # database (see TrainingSetting's spec), so start each example empty.
  before { described_class.delete_all }

  describe '.current' do
    it 'creates the singleton row on first access, with no number set' do
      expect { described_class.current }.to change(described_class, :count).from(0).to(1)
      expect(described_class.current.phone_number).to be_nil
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

  it 'normalizes the human-friendly formats staff type' do
    setting = described_class.current

    setting.update!(phone_number: ' +92 (300) 123-4567 ')

    expect(setting.phone_number).to eq('+923001234567')
  end

  it 'clears a blank number back to nil' do
    setting = described_class.current
    setting.update!(phone_number: '+923001234567')

    setting.update!(phone_number: '   ')

    expect(setting.phone_number).to be_nil
  end

  it 'rejects something that is not a phone number' do
    setting = described_class.current

    expect(setting.update(phone_number: 'call us')).to be(false)
    expect(setting.errors[:phone_number]).to be_present
  end

  it 'cannot be destroyed' do
    expect { described_class.current.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'refuses a second row at the database level' do
    described_class.current

    expect { described_class.create!(singleton_guard: true) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
