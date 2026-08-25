# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditEvent, type: :model do
  subject(:audit_event) { build(:audit_event) }

  it { is_expected.to belong_to(:candidate).optional }
  it { is_expected.to belong_to(:candidate_assignment).optional }
  it { is_expected.to belong_to(:actor).class_name('User').optional }

  it 'is immutable after creation' do
    persisted_audit_event = create(:audit_event)

    expect { persisted_audit_event.update!(note: 'Changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { persisted_audit_event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'keeps candidate and assignment references consistent' do
    another_candidate = create(:candidate)
    audit_event.candidate = another_candidate

    expect(audit_event).not_to be_valid
    expect(audit_event.errors[:candidate_assignment]).to include('is invalid')
  end

  it 'requires metadata to be present' do
    audit_event.metadata = nil

    expect(audit_event).not_to be_valid
    expect(audit_event.errors[:metadata]).to be_present
  end
end
