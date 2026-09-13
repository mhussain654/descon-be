# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::WorkflowStageCallScriptPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index? and #update?' do
    it 'allows staff with manage_ai_call_scripts (admin, hr, mps)' do
      %w[admin hr mps].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, WorkflowStageCallScript).index?).to be(true)
        expect(described_class.new(actor, WorkflowStageCallScript).update?).to be(true)
      end
    end

    it 'denies staff without manage_ai_call_scripts' do
      %w[finance management].each do |role|
        actor = create(:user, role:)
        expect(described_class.new(actor, WorkflowStageCallScript).index?).to be(false)
      end
    end

    it 'denies an unauthenticated actor' do
      expect(described_class.new(nil, WorkflowStageCallScript).index?).to be(false)
    end
  end

  describe '::Scope' do
    it 'resolves the full scope for a permitted actor and none for a denied one' do
      admin = create(:user, role: 'admin')
      finance = create(:user, role: 'finance')
      create(:workflow_stage_call_script)

      expect(described_class::Scope.new(admin, WorkflowStageCallScript.all).resolve.count).to eq(1)
      expect(described_class::Scope.new(finance, WorkflowStageCallScript.all).resolve.count).to eq(0)
    end
  end
end
