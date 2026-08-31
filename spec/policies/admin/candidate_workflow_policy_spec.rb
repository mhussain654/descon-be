# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateWorkflowPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  let(:candidate) { create(:candidate) }

  it 'allows workflow reads for workflow-view roles and writes only for workflow-manage roles' do
    admin = create(:user, role: 'admin')
    hr = create(:user, role: 'hr')
    mps = create(:user, role: 'mps')
    finance = create(:user, role: 'finance')
    management = create(:user, role: 'management')

    expect(described_class.new(admin, candidate).show?).to be(true)
    expect(described_class.new(admin, candidate).history?).to be(true)
    expect(described_class.new(admin, candidate).index_transitions?).to be(true)
    expect(described_class.new(admin, candidate).create_transition?).to be(true)
    expect(described_class.new(admin, candidate).access?).to be(true)

    expect(described_class.new(mps, candidate).show?).to be(true)
    expect(described_class.new(mps, candidate).history?).to be(true)
    expect(described_class.new(mps, candidate).index_transitions?).to be(true)
    expect(described_class.new(mps, candidate).create_transition?).to be(true)
    expect(described_class.new(mps, candidate).access?).to be(true)

    expect(described_class.new(hr, candidate).show?).to be(true)
    expect(described_class.new(hr, candidate).history?).to be(true)
    expect(described_class.new(hr, candidate).index_transitions?).to be(true)
    expect(described_class.new(hr, candidate).create_transition?).to be(false)
    expect(described_class.new(hr, candidate).access?).to be(true)

    expect(described_class.new(finance, candidate).show?).to be(true)
    expect(described_class.new(finance, candidate).history?).to be(true)
    expect(described_class.new(finance, candidate).index_transitions?).to be(true)
    expect(described_class.new(finance, candidate).create_transition?).to be(false)
    expect(described_class.new(finance, candidate).access?).to be(true)

    expect(described_class.new(management, candidate).show?).to be(true)
    expect(described_class.new(management, candidate).history?).to be(true)
    expect(described_class.new(management, candidate).index_transitions?).to be(true)
    expect(described_class.new(management, candidate).create_transition?).to be(false)
    expect(described_class.new(management, candidate).access?).to be(true)
  end
end
