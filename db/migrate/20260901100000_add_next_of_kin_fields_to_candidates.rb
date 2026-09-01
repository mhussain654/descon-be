# frozen_string_literal: true

class AddNextOfKinFieldsToCandidates < ActiveRecord::Migration[8.0]
  def change
    add_next_of_kin_columns
    add_next_of_kin_constraints
  end

  private

  def add_next_of_kin_columns
    change_table(:candidates, bulk: true) do |table|
      table.string :next_of_kin_name
      table.string :next_of_kin_relationship
      table.string :next_of_kin_mobile_number
      table.string :next_of_kin_cnic
    end
  end

  def add_next_of_kin_constraints
    add_check_constraint(
      :candidates,
      "next_of_kin_mobile_number IS NULL OR next_of_kin_mobile_number ~ '^\\+?\\d{10,15}$'",
      name: 'candidates_next_of_kin_mobile_number_format'
    )
    add_check_constraint(
      :candidates,
      "next_of_kin_cnic IS NULL OR next_of_kin_cnic ~ '^\\d{5}-\\d{7}-\\d$'",
      name: 'candidates_next_of_kin_cnic_format'
    )
  end
end
