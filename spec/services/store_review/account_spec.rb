# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreReview::Account do
  let(:reviewer_cnic) { '12345-6789012-3' }
  let(:reviewer_code) { '246810' }

  def configure(cnic:, otp_code:)
    allow(described_class).to receive(:setting).with(:cnic).and_return(cnic)
    allow(described_class).to receive(:setting).with(:otp_code).and_return(otp_code)
  end

  def create_reviewer
    StoreReview::CreateCandidateService.call(created_by: create(:user, role: 'admin'))
  end

  def request_code(cnic) = CandidateAuthentication::Otp::RequestService.call(cnic:, ip_address: '127.0.0.1')

  def verify(cnic, code)
    CandidateAuthentication::Otp::VerifyService.call(cnic:, code:, user_agent: 'spec', ip_address: '127.0.0.1')
  end

  before do
    create(:project, code: 'qatar_infrastructure') unless Project.exists?(code: 'qatar_infrastructure')
    create(:craft, code: 'electrician') unless Craft.exists?(code: 'electrician')
    allow(Sms::SendMessage).to receive(:call)
  end

  context 'when the credentials are not set' do
    before { configure(cnic: '', otp_code: '') }

    it 'is off and creates no reviewer candidate' do
      expect(described_class).not_to be_enabled
      expect { create_reviewer }.to raise_error(StoreReview::CreateCandidateService::NotConfiguredError)
    end
  end

  context 'when a credential is malformed' do
    before { configure(cnic: reviewer_cnic, otp_code: '12') }

    it 'is off' do
      expect(described_class).not_to be_enabled
      expect(described_class.cnic?(reviewer_cnic)).to be(false)
    end
  end

  context 'when configured' do
    before { configure(cnic: reviewer_cnic.delete('-'), otp_code: reviewer_code) }

    it 'creates the reviewer on the Qatar flow at Enrolled, once' do
      candidate = create_reviewer

      expect(create_reviewer).to eq(candidate)
      expect(candidate.cnic).to eq(reviewer_cnic)
      expect(candidate.current_assignment).to have_attributes(
        country: Country.find_by!(code: 'qatar'), current_workflow_stage: WorkflowStage.find_by!(code: 'registered')
      )
      expect(AuditEvent.where(action_code: 'store_review_candidate_created').count).to eq(1)
    end

    it 'signs the reviewer in with the fixed code, sends no SMS and audits the sign-in' do
      candidate = create_reviewer

      request_code(reviewer_cnic)
      result = verify(reviewer_cnic, reviewer_code)

      expect(result[:candidate]).to eq(candidate)
      expect(Sms::SendMessage).not_to have_received(:call)
      expect(AuditEvent.where(candidate:, action_code: 'store_review_signed_in').count).to eq(1)
    end

    it 'lets the reviewer sign in again straight away once the code has been used' do
      create_reviewer
      request_code(reviewer_cnic)
      verify(reviewer_cnic, reviewer_code)

      request_code(reviewer_cnic)

      expect(verify(reviewer_cnic, reviewer_code)[:access_token]).to be_present
    end

    it 'still rejects a wrong code and keeps the attempt limit' do
      create_reviewer
      request_code(reviewer_cnic)

      expect { verify(reviewer_cnic, '000000') }.to raise_error(OtpInvalidError)
      expect(CandidateOtpChallenge.where(cnic: reviewer_cnic).last.attempts).to eq(1)
    end

    it 'keeps the reviewer at Enrolled when a workflow event would advance them' do
      candidate = create_reviewer

      CandidateWorkflows::AutomaticTransitionService.call(candidate:, event: :documents_uploaded)

      expect(candidate.current_assignment.reload.current_workflow_stage.code).to eq('registered')
    end

    it 'leaves other candidates on the normal random code with an SMS' do
      other = create(:candidate)
      allow(Sms::SendMessage).to receive(:call).and_return(Sms::DeliveryResult.new(success: true))

      request_code(other.cnic)

      expect(Sms::SendMessage).to have_received(:call).once
      expect { verify(other.cnic, reviewer_code) }.to raise_error(OtpInvalidError)
    end
  end
end
