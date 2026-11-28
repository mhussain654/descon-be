# frozen_string_literal: true

# Which sender each candidate's SMS go out from: the "DESCON MPS" brand name
# (masking) by default, or the short code for a number whose network blocks
# the brand name. Adding a column with a constant default does not rewrite
# the table in PostgreSQL, so this is safe on the live candidates table.
class AddSmsSenderToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :sms_sender, :string, null: false, default: 'masking'
    add_check_constraint :candidates, "sms_sender IN ('masking', 'short_code')", name: 'candidates_sms_sender_check'
  end
end
