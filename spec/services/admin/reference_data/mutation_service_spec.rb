# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::ReferenceData::MutationService do
  before { ensure_staff_authorization_reference_data! }

  let(:actor) { create(:user, role: 'hr') }

  it 'creates an active reference value and records safe audit metadata' do
    record = described_class.call(
      actor:, record: nil, record_class: Country, action: :create,
      attributes: { code: 'mps_301_country', name_en: 'MPS Country', name_ur: 'ایم پی ایس ملک' },
      request_id: 'request-1'
    )

    expect(record).to be_active
    expect(AuditEvent.last).to have_attributes(action_code: 'reference_data_create', entity_type: 'ReferenceData')
    expect(AuditEvent.last.metadata).to include('reference_type' => 'country', 'code' => 'mps_301_country')
  end

  it 'rejects a stale update without changing the reference value' do
    country = create(:country, code: 'mps_301_stale')

    expect do
      described_class.call(
        actor:, record: country, record_class: Country, action: :update,
        attributes: { name_en: 'Changed' }, expected_updated_at: 1.hour.ago.utc.iso8601
      )
    end.to raise_error(StaleReferenceDataError)

    expect(country.reload.name_en).not_to eq('Changed')
  end

  it 'retires rather than destroys a referenced value' do
    country = create(:country, code: 'mps_301_retired')
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, country:)

    described_class.call(actor:, record: country, record_class: Country, action: :retire, attributes: {})

    expect(country.reload).not_to be_active
    expect(candidate.current_assignment.country).to eq(country)
  end
end
