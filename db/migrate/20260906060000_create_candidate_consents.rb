# frozen_string_literal: true

# Records a candidate's acknowledgment of a specific policy version (MPS-204:
# "Record consent during registration with timestamp, policy version and
# evidence"). Immutable via ImmutableRecord -- once accepted, a consent
# record can never be edited, only superseded by a new row for a newer
# policy version.
class CreateCandidateConsents < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_consents do |t|
      t.references :candidate, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :policy_version, null: false
      t.datetime :accepted_at, null: false
      t.string :ip_address

      t.timestamps
    end

    add_index :candidate_consents, :public_id, unique: true
    add_index :candidate_consents, %i[candidate_id policy_version], unique: true

    add_check_constraint :candidate_consents,
                         "public_id::text ~ '^[0-9a-f-]{36}$'::text",
                         name: 'candidate_consents_public_id_format'
  end
end
