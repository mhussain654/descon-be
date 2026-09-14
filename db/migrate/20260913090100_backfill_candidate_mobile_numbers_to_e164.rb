# frozen_string_literal: true

# Backfills existing Candidate#mobile_number values into the canonical E.164
# form PhoneNumbers::Normalizer now produces going forward (see
# app/services/phone_numbers/normalizer.rb) -- inbound AI-call caller-ID
# matching and outbound call `to_number` both compare/send this column as a
# raw string, so a pre-existing local-format value ('03001234567') would
# never match a caller-ID reported in E.164 ('+923001234567') until backfilled.
#
# The normalization is duplicated here (rather than calling
# PhoneNumbers::Normalizer) deliberately -- a migration must keep working
# unchanged even if the app-level normalizer's rules evolve later.
class BackfillCandidateMobileNumbersToE164 < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  COUNTRY_CODE = '92'
  LOCAL_TRUNK_PREFIX = '0'
  FULL_DIGITS_LENGTH = 12

  class MigrationCandidate < ApplicationRecord
    self.table_name = 'candidates'
  end

  def up
    MigrationCandidate.find_each do |candidate|
      backfill_one!(candidate)
    end
  end

  def down
    # Not reversible -- the original local/international spelling each
    # candidate originally submitted in is not recoverable once normalized.
  end

  private

  # `mobile_number` has no database uniqueness constraint (only an app-level
  # `validates ... uniqueness: true` on Candidate, which `update_column`
  # deliberately bypasses for a bulk backfill) -- so two previously-distinct
  # values (e.g. '03001234567' and '+923001234567') can normalize to the
  # same E.164 string without ever raising `RecordNotUnique`. Inbound AI-call
  # caller-ID lookup (`Candidate.active.find_by(mobile_number:)`) would then
  # silently resolve to an arbitrary one of the colliding rows. Detect the
  # collision explicitly before writing, and skip + report it loudly instead
  # of writing a value that already belongs to another candidate -- cleaning
  # up any pre-existing duplicate is a separate, consequential data decision
  # (which row is canonical) that this migration must not make unilaterally.
  def backfill_one!(candidate)
    normalized = normalize(candidate.mobile_number)
    return if normalized.blank? || normalized == candidate.mobile_number

    colliding_id = MigrationCandidate.where(mobile_number: normalized).where.not(id: candidate.id).pick(:id)
    return report_collision!(candidate, colliding_id) if colliding_id.present?

    candidate.update_column(:mobile_number, normalized) # rubocop:disable Rails/SkipsModelValidations -- data backfill
  end

  def report_collision!(candidate, colliding_id)
    Rails.logger.warn(
      "[BackfillCandidateMobileNumbersToE164] skipped candidate ##{candidate.id}: " \
      "normalizing its mobile_number would collide with existing candidate ##{colliding_id} -- " \
      'resolve this duplicate manually before either row can be safely normalized'
    )
  end

  def normalize(raw_number)
    raw_value = raw_number.to_s.strip
    digits = raw_value.gsub(/\D/, '')
    return '' if digits.blank?

    "+#{country_coded_digits(raw_value:, digits:)}"
  end

  def country_coded_digits(raw_value:, digits:)
    return digits if raw_value.start_with?('+')
    return digits if digits.start_with?(COUNTRY_CODE) && digits.length == FULL_DIGITS_LENGTH
    return "#{COUNTRY_CODE}#{digits[1..]}" if digits.start_with?(LOCAL_TRUNK_PREFIX)

    "#{COUNTRY_CODE}#{digits}"
  end
end
