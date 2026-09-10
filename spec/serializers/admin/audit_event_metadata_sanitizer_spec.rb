# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::AuditEventMetadataSanitizer do
  describe '.sanitize' do
    it 'keeps an approved id/code/date/count key with its value unchanged' do
      metadata = {
        'candidate_public_id' => 'abc-123',
        'provider_status_code' => 'settled',
        'checkout_expires_at' => '2026-09-07T00:00:00Z',
        'total_rows' => 42
      }

      expect(described_class.sanitize(metadata)).to eq(metadata)
    end

    it 'drops a blocked key even when its value looks harmless' do
      expect(described_class.sanitize('reason' => 'x', 'field' => 'status_code')).to eq({})
    end

    %w[reason field previous_value new_value before after details evidence].each do |key|
      it "always drops the sensitive key \"#{key}\"" do
        expect(described_class.sanitize(key => 'anything')).to eq({})
      end
    end

    it 'drops a key that matches no approved suffix or exact name' do
      expect(described_class.sanitize('some_future_unreviewed_field' => 'x')).to eq({})
    end

    it 'never renders a nested object, even under an approved-looking key' do
      result = described_class.sanitize('metadata_code' => { 'role' => 'admin', 'staff_state' => 'active' })

      expect(result['metadata_code']).to eq('(unavailable)')
    end

    it 'summarizes an array of nested objects by count rather than exposing their contents' do
      result = described_class.sanitize('required_requirement_codes' => [{ 'a' => 1 }, { 'b' => 2 }])

      expect(result['required_requirement_codes']).to eq('(2 items)')
    end

    it 'keeps an array of primitive values as-is' do
      result = described_class.sanitize('required_requirement_codes' => %w[passport cnic_front])

      expect(result['required_requirement_codes']).to eq(%w[passport cnic_front])
    end

    it 'keeps null values' do
      expect(described_class.sanitize('completed_at' => nil)).to eq('completed_at' => nil)
    end

    it 'returns an empty hash for blank metadata' do
      expect(described_class.sanitize({})).to eq({})
      expect(described_class.sanitize(nil)).to eq({})
    end

    it 'drops a nested object under before/after even though it would otherwise be an approved shape' do
      result = described_class.sanitize('before' => { 'role' => 'hr' }, 'after' => { 'role' => 'admin' },
                                        'status_code' => 'role_updated')

      expect(result).to eq('status_code' => 'role_updated')
    end
  end
end
