# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RolePermission, type: :model do
  subject(:role_permission) { create(:role_permission) }

  it { is_expected.to belong_to(:role) }
  it { is_expected.to belong_to(:permission) }
  it { is_expected.to validate_uniqueness_of(:permission_id).scoped_to(:role_id) }
end
