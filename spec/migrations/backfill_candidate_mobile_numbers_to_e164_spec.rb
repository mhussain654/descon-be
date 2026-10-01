# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260913090100_backfill_candidate_mobile_numbers_to_e164')

RSpec.describe BackfillCandidateMobileNumbersToE164 do
  subject(:migration) { described_class.new }

  def candidate_with_raw_mobile_number(raw_number)
    candidate = create(:candidate)
    candidate.update_column(:mobile_number, raw_number) # rubocop:disable Rails/SkipsModelValidations -- simulating a pre-existing raw value
    candidate
  end

  describe '#up' do
    it 'normalizes a local-format number to E.164' do
      candidate = candidate_with_raw_mobile_number('03001234567')

      migration.up

      expect(candidate.reload.mobile_number).to eq('+923001234567')
    end

    it 'leaves an already-E.164 number untouched' do
      candidate = candidate_with_raw_mobile_number('+923001234567')

      migration.up

      expect(candidate.reload.mobile_number).to eq('+923001234567')
    end

    # Regression: 'mobile_number' has no database uniqueness constraint, so
    # two distinct raw values that normalize to the same E.164 string must
    # not both silently become that value -- the previous implementation's
    # `rescue ActiveRecord::RecordNotUnique` was unreachable dead code (no
    # unique index exists to raise it), so this collision went completely
    # undetected.
    it 'does not overwrite a candidate whose normalized number would collide with another candidate' do
      colliding_target = candidate_with_raw_mobile_number('+923001234567')
      candidate = candidate_with_raw_mobile_number('03001234567')

      migration.up

      expect(candidate.reload.mobile_number).to eq('03001234567')
      expect(colliding_target.reload.mobile_number).to eq('+923001234567')
    end

    it 'logs a warning naming both candidates when a collision is skipped' do
      colliding_target = candidate_with_raw_mobile_number('+923001234567')
      candidate = candidate_with_raw_mobile_number('03001234567')
      allow(Rails.logger).to receive(:warn)

      migration.up

      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/##{candidate.id}.*##{colliding_target.id}/))
    end

    it 'still normalizes every other candidate when one collision is skipped' do
      candidate_with_raw_mobile_number('+923001234567')
      colliding_candidate = candidate_with_raw_mobile_number('03001234567')
      unrelated_candidate = candidate_with_raw_mobile_number('03009998888')

      migration.up

      expect(colliding_candidate.reload.mobile_number).to eq('03001234567')
      expect(unrelated_candidate.reload.mobile_number).to eq('+923009998888')
    end
  end

  describe '#down' do
    it 'is a no-op (not reversible)' do
      candidate = candidate_with_raw_mobile_number('03001234567')
      migration.up

      expect { migration.down }.not_to raise_error
      expect(candidate.reload.mobile_number).to eq('+923001234567')
    end
  end
end
