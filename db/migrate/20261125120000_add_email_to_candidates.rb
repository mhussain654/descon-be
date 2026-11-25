# frozen_string_literal: true

# Candidates can add an email address in the app's Profile tab, so staff can
# reach them by email. Optional: existing candidates have none.
class AddEmailToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :email, :string
  end
end
