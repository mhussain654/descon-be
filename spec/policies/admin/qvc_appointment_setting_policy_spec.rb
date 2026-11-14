# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::QvcAppointmentSettingPolicy do
  before { ensure_staff_authorization_reference_data! }

  describe '#show? and #update?' do
    it 'allows staff who move candidates through the workflow (manage_workflow)' do
      %w[admin mps developer].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, QvcAppointmentSetting).show?).to be(true)
        expect(described_class.new(actor, QvcAppointmentSetting).update?).to be(true)
      end
    end

    it 'denies roles without manage_workflow and an unauthenticated actor' do
      %w[hr finance management].each do |role|
        expect(described_class.new(create(:user, role:), QvcAppointmentSetting).update?).to be(false)
      end
      expect(described_class.new(nil, QvcAppointmentSetting).show?).to be(false)
    end
  end
end
