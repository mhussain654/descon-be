# frozen_string_literal: true

# Adds the first approved RoboCall voices as call types and sets them on their
# workflow stages (stages stay switched off). The list lives in
# AiCalls::InstallStarterRobocallVoicesService. Nothing to undo: the voices are
# ordinary admin-editable rows, and batches may already refer to them.
class InstallStarterRobocallVoices < ActiveRecord::Migration[8.1]
  def up
    AiCalls::InstallStarterRobocallVoicesService.call
  end

  def down; end
end
