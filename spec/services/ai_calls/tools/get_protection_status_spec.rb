# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::GetProtectionStatus do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:call_record) do
    create(:candidate_ai_call, :inbound, verification_status: 'verified', candidate:, candidate_assignment: assignment)
  end

  it 'returns not_yet_scheduled with a spoken label when no protection record exists' do
    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:status]).to eq('not_yet_scheduled')
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.protection_statuses.not_yet_scheduled'))
  end

  it 'labels an appeared-but-not-yet-protected record as awaiting outcome' do
    record = create(:candidate_protection_record, candidate_assignment: assignment, appeared_on: Date.current,
                                                  appeared_recorded_at: Time.current,
                                                  appeared_recorded_by: assignment.created_by)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:id]).to eq(record.public_id)
    expect(result[:appeared_on]).to eq(record.appeared_on.iso8601)
    expect(result[:status]).to eq('appeared_awaiting_outcome')
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.protection_statuses.appeared_awaiting_outcome'))
  end

  it 'labels a fully cleared record as ready to fly' do
    record = create(:candidate_protection_record, candidate_assignment: assignment, appeared_on: Date.current,
                                                  appeared_recorded_at: Time.current,
                                                  appeared_recorded_by: assignment.created_by,
                                                  protected_on: Date.current, ready_to_fly_at: Time.current,
                                                  ready_recorded_by: assignment.created_by)

    result = described_class.call(candidate_ai_call: call_record)

    expect(result[:id]).to eq(record.public_id)
    expect(result[:status]).to eq('ready_to_fly')
    expect(result[:status_label]).to eq(I18n.t('api.ai_calls.labels.protection_statuses.ready_to_fly'))
  end
end
