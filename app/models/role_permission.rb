# frozen_string_literal: true

# Join model granting a single permission to a single role.
class RolePermission < ApplicationRecord
  belongs_to :role
  belongs_to :permission

  validates :permission_id, uniqueness: { scope: :role_id }
end
