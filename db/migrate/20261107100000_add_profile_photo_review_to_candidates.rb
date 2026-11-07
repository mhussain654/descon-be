# frozen_string_literal: true

# Staff approve or reject a candidate's profile photo (it must clearly show the
# candidate's own face). A new upload waits for review; a rejected photo is
# removed and the status stays "rejected" so the app can tell the candidate why.
class AddProfilePhotoReviewToCandidates < ActiveRecord::Migration[8.1]
  STATUS_CHECK = "profile_photo_status IS NULL OR profile_photo_status IN ('pending', 'approved', 'rejected')"

  def change
    change_table :candidates, bulk: true do |t|
      t.string :profile_photo_status
      t.datetime :profile_photo_reviewed_at
      t.references :profile_photo_reviewed_by, foreign_key: { to_table: :users }, index: true
      t.check_constraint STATUS_CHECK, name: 'candidates_profile_photo_status'
    end

    reversible { |dir| dir.up { mark_existing_photos_pending } }
  end

  private

  # Photos uploaded before review existed wait for staff like new ones.
  def mark_existing_photos_pending
    execute <<~SQL.squish
      UPDATE candidates SET profile_photo_status = 'pending'
      WHERE id IN (SELECT record_id FROM active_storage_attachments
                   WHERE record_type = 'Candidate' AND name = 'profile_photo')
    SQL
  end
end
