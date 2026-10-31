# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::SmsTemplatePolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index? and #update?' do
    it 'allows only the developer (manage_app_settings is developer-only)' do
      developer = create(:user, role: 'developer')

      expect(described_class.new(developer, SmsTemplate).index?).to be(true)
      expect(described_class.new(developer, SmsTemplate).update?).to be(true)
    end

    it 'denies every other role' do
      %w[admin hr mps finance management].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, SmsTemplate).index?).to be(false)
        expect(described_class.new(actor, SmsTemplate).update?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, SmsTemplate).index?).to be(false)
    end
  end

  describe 'Scope' do
    it 'returns every row to the developer and none to anyone else' do
      template = create(:sms_template)

      expect(described_class::Scope.new(create(:user, role: 'developer'), SmsTemplate).resolve).to include(template)
      expect(described_class::Scope.new(create(:user, role: 'admin'), SmsTemplate).resolve).to be_empty
    end
  end
end
