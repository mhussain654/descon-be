# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateSms::UpdateSender do
  let(:actor) { create(:user) }
  let(:candidate) { create(:candidate) }

  def update(sms_sender) = described_class.call(candidate:, sms_sender:, actor:, request_id: 'req-1')

  it 'moves the candidate to the short code and audits the change' do
    expect { update('short_code') }.to change(AuditEvent, :count).by(1)

    expect(candidate.reload.sms_sender).to eq('short_code')
    expect(AuditEvent.last).to have_attributes(
      actor:, candidate:, action_code: 'candidate_sms_sender_changed', request_id: 'req-1',
      metadata: { 'candidate_public_id' => candidate.public_id, 'from' => 'masking', 'to' => 'short_code' }
    )
  end

  it 'changes nothing when the sender is already set' do
    expect { update('masking') }.not_to change(AuditEvent, :count)
    expect(candidate.reload.sms_sender).to eq('masking')
  end

  it 'rejects an unknown sender' do
    expect { update('whatsapp') }.to raise_error(ValidationError) { |error|
      expect(error.field).to eq('sms_sender.sender')
    }
    expect(candidate.reload.sms_sender).to eq('masking')
  end
end
