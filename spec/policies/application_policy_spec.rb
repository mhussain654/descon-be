# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationPolicy do
  subject(:policy) { described_class.new(user, record) }

  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:user) }

  describe 'default permissions' do
    it 'denies index, show, create, update, and destroy' do
      expect(policy.index?).to be(false)
      expect(policy.show?).to be(false)
      expect(policy.create?).to be(false)
      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
    end

    it 'delegates new? to create? and edit? to update?' do
      expect(policy.new?).to be(false)
      expect(policy.edit?).to be(false)
    end
  end

  describe described_class::Scope do
    subject(:scope) { described_class.new(user, User) }

    it 'raises until resolve is implemented' do
      expect { scope.resolve }.to raise_error(NoMethodError, /You must define #resolve/)
    end
  end
end
