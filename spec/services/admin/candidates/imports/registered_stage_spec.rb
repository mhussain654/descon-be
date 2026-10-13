# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::Imports::RegisteredStage do
  describe '.normalize' do
    it 'maps blank values to registered' do
      expect([nil, '', '   '].map { |value| described_class.normalize(value) }).to all(eq('registered'))
    end

    it 'maps common "Not Registered" spellings and formats to registered' do
      values = ['Not Registred', 'not registered', 'NOT_REGISTERED', 'not-registered', ' Not  Registered ',
                'notregistered']

      expect(values.map { |value| described_class.normalize(value) }).to all(eq('registered'))
    end

    it 'passes any other value through as a trimmed, lowercased code' do
      expect(described_class.normalize(' Documents_Pending ')).to eq('documents_pending')
      expect(described_class.normalize('registered')).to eq('registered')
    end

    it 'does not treat other labels that merely mention registration as registered' do
      expect(described_class.normalize('Not Yet Registered')).to eq('not yet registered')
    end
  end
end
