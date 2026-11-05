# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CandidateBankDetails::DecisionService do
  before { ensure_canonical_workflow_stages! }

  let(:actor) { create(:user, role: 'finance') }
  let(:candidate) { create(:candidate, preferred_locale: 'ur') }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let!(:bank_detail) { create(:candidate_bank_detail, candidate_assignment: assignment) }

  def decide(decision, reason: nil)
    described_class.call(actor:, candidate:, decision:, rejection_reason: reason, request_id: 'req-bank-1')
  end

  describe '.call' do
    it 'verifies the current bank details, recording who did it and an audit event' do
      result = decide('verified')

      expect(result.reload).to have_attributes(status_code: 'verified', reviewed_by: actor, rejection_reason: nil,
                                               reviewed_at: be_present)
      expect(AuditEvent.find_by!(action_code: 'candidate_bank_detail_verified').entity_id).to eq(bank_detail.id)
    end

    it 'moves the workflow on, since the bank details may complete the review' do
      allow(CandidateWorkflows::AutomaticTransitionService).to receive(:call)

      decide('verified')

      expect(CandidateWorkflows::AutomaticTransitionService).to have_received(:call)
        .with(candidate:, event: :documents_reviewed, actor:, request_id: 'req-bank-1')
    end

    it 'rejects with a reason the candidate sees, and queues the rejection SMS naming the bank details' do
      decide('rejected', reason: 'The IBAN does not match the cheque.')

      expect(bank_detail.reload).to have_attributes(status_code: 'rejected',
                                                    rejection_reason: 'The IBAN does not match the cheque.')
      expect(CandidateSmsDelivery.find_by!(dedupe_key: "bank_detail_rejected:#{bank_detail.id}"))
        .to have_attributes(message_code: 'document_rejected',
                            variables: include('document' => 'بینک اکاؤنٹ کی تفصیلات'))
    end

    it 'requires a plain-text reason of a sensible length to reject' do
      expect { decide('rejected') }.to raise_error(RejectionReasonRequiredError)
      expect { decide('rejected', reason: 'short') }.to raise_error(RejectionReasonInvalidError)
      expect { decide('rejected', reason: '<b>Wrong IBAN given here</b>') }.to raise_error(RejectionReasonInvalidError)
      expect(bank_detail.reload.status_code).to eq('submitted')
    end

    it 'refuses details already reviewed' do
      decide('verified')

      expect { decide('rejected', reason: 'The IBAN does not match the cheque.') }
        .to raise_error(DocumentAlreadyReviewedError)
    end

    it 'refuses a candidate without bank details' do
      bank_detail.destroy!

      expect { decide('verified') }.to raise_error(CandidateBankDetailNotFoundError)
    end
  end
end
