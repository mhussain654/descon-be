# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Deployment::CheckResult do
  describe '#to_s' do
    it 'renders the status, name and detail on one line' do
      result = described_class.new(name: 'storage', status: :warn, detail: 'static keys set')

      expect(result.to_s).to eq('[WARN] storage: static keys set')
    end
  end

  describe '#failed?' do
    it 'is true only for the fail status' do
      expect(described_class.new(name: 'a', status: :fail, detail: 'x')).to be_failed
      expect(described_class.new(name: 'a', status: :warn, detail: 'x')).not_to be_failed
      expect(described_class.new(name: 'a', status: :pass, detail: 'x')).not_to be_failed
    end
  end

  context 'with an unknown status' do
    it 'raises so a typo cannot be reported as a pass' do
      expect do
        described_class.new(name: 'a', status: :ok, detail: 'x')
      end.to raise_error(ArgumentError, /unknown status/)
    end
  end
end
