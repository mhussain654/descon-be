# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrainingSetting do
  describe '.current' do
    it 'creates the singleton row on first access, seeded with the default URL' do
      expect { described_class.current }.to change(described_class, :count).from(0).to(1)
      expect(described_class.current.url).to eq(described_class::DEFAULT_URL)
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

    expect do
      described_class.create!(singleton_guard: true, url: 'https://example.test')
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'requires a URL' do
    setting = described_class.current

    expect(setting.update(url: nil)).to be(false)
    expect(setting.update(url: '')).to be(false)
  end

  it 'requires the URL to be http(s)' do
    setting = described_class.current

    expect(setting.update(url: 'not a url')).to be(false)
    expect(setting.update(url: 'ftp://example.test/file')).to be(false)
    expect(setting.update(url: 'javascript:alert(1)')).to be(false)
    expect(setting.update(url: 'http://example.test')).to be(true)
    expect(setting.update(url: 'https://example.test/path?query=1')).to be(true)
  end
end
