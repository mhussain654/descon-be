# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::Registry do
  describe '.fetch' do
    {
      'verify_caller_identity' => AiCalls::Tools::VerifyCallerIdentity,
      'get_application_status' => AiCalls::Tools::GetApplicationStatus,
      'get_missing_documents' => AiCalls::Tools::GetMissingDocuments,
      'get_payment_status' => AiCalls::Tools::GetPaymentStatus,
      'get_qvc_status' => AiCalls::Tools::GetQvcStatus,
      'get_visa_status' => AiCalls::Tools::GetVisaStatus,
      'get_protection_status' => AiCalls::Tools::GetProtectionStatus,
      'get_flight_information' => AiCalls::Tools::GetFlightInformation,
      'create_callback_request' => AiCalls::Tools::CreateCallbackRequest,
      'transfer_to_human' => AiCalls::Tools::TransferToHuman
    }.each do |tool_name, handler_class|
      it "resolves #{tool_name} to #{handler_class}" do
        expect(described_class.fetch(tool_name)).to eq(handler_class)
      end
    end

    it 'accepts a symbol tool name' do
      expect(described_class.fetch(:get_payment_status)).to eq(AiCalls::Tools::GetPaymentStatus)
    end

    it 'raises for an unknown tool name' do
      expect { described_class.fetch('not_a_real_tool') }.to raise_error(ArgumentError, /not_a_real_tool/)
    end
  end

  describe 'PRE_VERIFICATION_TOOLS' do
    it 'lists exactly the tools reachable before verification succeeds' do
      expect(described_class::PRE_VERIFICATION_TOOLS)
        .to contain_exactly('verify_caller_identity', 'create_callback_request', 'transfer_to_human')
    end
  end
end
