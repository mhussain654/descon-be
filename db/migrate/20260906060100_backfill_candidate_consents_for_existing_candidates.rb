# frozen_string_literal: true

# The consent gate (Candidates::Consents::RecordService, ProtectedController's
# ensure_consent_given!) blocks every candidate API call once it's live, so
# every candidate created before this deploy needs a synthetic already-accepted
# consent row for the launch policy version -- otherwise existing demo/production
# candidates would be retroactively locked out of their own accounts by a policy
# that didn't exist when they registered. New candidates going forward accept for
# real during registration/first login; this is a one-time migration-era backfill
# only.
class BackfillCandidateConsentsForExistingCandidates < ActiveRecord::Migration[8.1]
  class Candidate < ApplicationRecord
    self.table_name = 'candidates'
  end

  class CandidateConsent < ApplicationRecord
    self.table_name = 'candidate_consents'
  end

  LAUNCH_POLICY_VERSION = '2026-09-06'

  def up
    now = Time.current

    Candidate.find_in_batches(batch_size: 1000) do |batch|
      rows = batch.map do |candidate|
        {
          candidate_id: candidate.id,
          public_id: SecureRandom.uuid,
          policy_version: LAUNCH_POLICY_VERSION,
          accepted_at: now,
          ip_address: nil,
          created_at: now,
          updated_at: now
        }
      end

      CandidateConsent.insert_all(rows) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    CandidateConsent.where(policy_version: LAUNCH_POLICY_VERSION, ip_address: nil).delete_all
  end
end
