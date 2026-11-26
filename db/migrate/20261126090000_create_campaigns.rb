# frozen_string_literal: true

# Candidate campaigns: the group a candidate's assignment belongs to (one import
# or intake, named by date and country), so staff can work on one campaign at a
# time. Each staff member's working campaign (`users.selected_campaign_id`, empty =
# all campaigns) narrows every candidate list, dashboard and report.
#
# One permanent Test campaign is created here, and the store reviewer's demo
# candidate (file number STORE-REVIEW) is put in it, so test data stays out
# of the real campaigns. Existing assignments stay without a campaign.
class CreateCampaigns < ActiveRecord::Migration[8.1]
  def up
    create_campaigns_table
    add_reference :candidate_assignments, :campaign, foreign_key: { to_table: :campaigns }
    add_reference :users, :selected_campaign, foreign_key: { to_table: :campaigns, on_delete: :nullify }

    create_test_campaign
  end

  def down
    remove_reference :users, :selected_campaign, foreign_key: { to_table: :campaigns }
    remove_reference :candidate_assignments, :campaign, foreign_key: { to_table: :campaigns }
    drop_table :campaigns
  end

  private

  def create_campaigns_table
    create_table :campaigns do |t|
      t.string :public_id, :code, :name, null: false
      t.string :kind, null: false, default: 'regular'
      t.references :country, foreign_key: true
      t.boolean :active, null: false, default: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    constrain_campaigns_table
  end

  # Unique ids and codes, at most one Test campaign, and a country on every regular campaign.
  def constrain_campaigns_table
    add_index :campaigns, :public_id, unique: true
    add_index :campaigns, :code, unique: true
    add_index :campaigns, :kind, unique: true, where: "kind = 'test'",
                                 name: 'index_campaigns_one_test_campaign'
    add_check_constraint :campaigns, "kind IN ('regular', 'test')", name: 'campaigns_kind'
    add_check_constraint :campaigns, "kind = 'test' OR country_id IS NOT NULL",
                         name: 'campaigns_regular_has_country'
  end

  def create_test_campaign
    execute <<~SQL.squish
      INSERT INTO campaigns (public_id, code, name, kind, active, created_at, updated_at)
      VALUES (#{connection.quote(SecureRandom.uuid)}, 'TEST', 'Test campaign', 'test', true, NOW(), NOW())
    SQL
    execute <<~SQL.squish
      UPDATE candidate_assignments SET campaign_id = (SELECT id FROM campaigns WHERE kind = 'test')
      WHERE reference_number = 'STORE-REVIEW'
    SQL
  end
end
