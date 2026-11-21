# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::AutomaticRejectionService do
  let(:document_type) do
    DocumentType.find_or_create_by!(code: 'cnic') do |type|
      type.name_en = 'CNIC'
      type.name_ur = 'شناختی کارڈ'
    end
  end
  let(:candidate) { create(:candidate, preferred_locale: 'en') }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:document) { create(:candidate_document, candidate_assignment: assignment, document_type:) }

  def switch_check(enabled)
    AppFeatureSetting.current.update!(document_identity_check_enabled: enabled)
  end

  before { switch_check(true) }

  it 'rejects a photo that is not an ID, with a reason in the candidate language, and tells them' do
    freeze_time do
      described_class.call(document:, identity: 'other_text')

      expect(document.reload).to have_attributes(
        status_code: 'rejected', rejected_automatically: true, verified_by: nil, verified_at: Time.current,
        rejection_reason: "This doesn't look like your CNIC. Please upload a clear photo of your CNIC."
      )
    end
    expect(AuditEvent.find_by(entity_id: document.id, action_code: 'candidate_document_rejected_automatically'))
      .to have_attributes(actor: nil)
    expect(CandidateSmsDelivery.find_by!(candidate:, message_code: 'document_rejected').variables)
      .to include('document' => 'CNIC')
  end

  it 'asks for a clearer photo when it could not read any text, in Urdu for an Urdu candidate' do
    candidate.update!(preferred_locale: 'ur')

    described_class.call(document:, identity: 'no_text')

    expect(document.reload.rejection_reason).to include('شناختی کارڈ')
  end

  it 'leaves anything that looks like an ID, or that OCR could not judge, for staff' do
    [['identity_document'], [nil]].each do |(identity)|
      described_class.call(document:, identity:)
      expect(document.reload.status_code).to eq('uploaded'), identity.inspect
    end
  end

  it 'does nothing while the switch is off' do
    switch_check(false)

    described_class.call(document:, identity: 'other_text')

    expect(document.reload.status_code).to eq('uploaded')
  end

  it 'never rejects a document staff already decided, or an older version' do
    reviewer = create(:user)
    verified = create(:candidate_document, document_type:, status_code: 'verified', verified_by: reviewer,
                                           verified_at: Time.current)
    replaced = create(:candidate_document, document_type:, superseded_at: Time.current)

    described_class.call(document: verified, identity: 'other_text')
    described_class.call(document: replaced, identity: 'other_text')

    expect(verified.reload.status_code).to eq('verified')
    expect(replaced.reload.status_code).to eq('uploaded')
  end

  it 'does not reject the same document type twice in a row, so a genuine unusual one reaches staff' do
    create(:candidate_document, candidate_assignment: assignment, document_type:, status_code: 'rejected',
                                rejected_automatically: true, verified_at: 1.hour.ago, uploaded_at: 1.hour.ago,
                                rejection_reason: 'Not a CNIC', superseded_at: 5.minutes.ago)

    described_class.call(document:, identity: 'other_text')

    expect(document.reload.status_code).to eq('uploaded')
  end
end
