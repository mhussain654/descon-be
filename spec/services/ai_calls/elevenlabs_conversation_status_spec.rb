# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::ElevenlabsConversationStatus do
  it 'classifies done and failed' do
    expect(described_class.classify('done')).to eq(:done)
    expect(described_class.classify('failed')).to eq(:failed)
  end

  it 'classifies each open status onto its local CandidateAiCall status' do
    expect(described_class.classify('initiated')).to eq('ringing')
    expect(described_class.classify('in-progress')).to eq('in_progress')
    expect(described_class.classify('processing')).to eq('processing')
  end

  it 'classifies anything else (including nil) as unknown' do
    expect(described_class.classify('something_new')).to eq(:unknown)
    expect(described_class.classify(nil)).to eq(:unknown)
  end
end
