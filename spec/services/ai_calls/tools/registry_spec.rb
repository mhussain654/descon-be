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
      'create_callback_request' => AiCalls::Tools::CreateCallbackRequest
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

    # Regression: live human transfer is handled entirely by ElevenLabs'
    # own transfer_to_number system tool (see AiCalls::AgentConfigs::Baseline),
    # not by a custom tool this dispatcher routes to.
    it 'no longer resolves transfer_to_human' do
      expect { described_class.fetch('transfer_to_human') }.to raise_error(ArgumentError, /transfer_to_human/)
    end
  end

  describe 'PRE_VERIFICATION_TOOLS' do
    it 'lists exactly the tools reachable before verification succeeds' do
      expect(described_class::PRE_VERIFICATION_TOOLS).to contain_exactly('verify_caller_identity',
                                                                         'create_callback_request')
    end
  end

  describe '.read_only_tool_names' do
    it 'lists exactly the 7 data-retrieval tools' do
      expect(described_class.read_only_tool_names).to contain_exactly(
        'get_application_status', 'get_missing_documents', 'get_payment_status', 'get_qvc_status',
        'get_visa_status', 'get_protection_status', 'get_flight_information'
      )
    end
  end
end
