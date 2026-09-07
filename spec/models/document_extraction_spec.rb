# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentExtraction, type: :model do
  subject(:extraction) { build(:document_extraction) }

  it { is_expected.to belong_to(:candidate_document) }
  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending succeeded failed]) }

  it 'enforces at most one pending or succeeded attempt per document at the database level' do
    document = create(:candidate_document)
    create(:document_extraction, candidate_document: document, status: 'pending')

    expect { create(:document_extraction, candidate_document: document, status: 'pending') }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'allows a fresh attempt after a prior one failed' do
    document = create(:candidate_document)
    create(:document_extraction, :failed, candidate_document: document)

    expect { create(:document_extraction, candidate_document: document, status: 'pending') }.not_to raise_error
  end

  describe '#succeeded?, #failed?, #pending?' do
    it 'reflects the status' do
      expect(build(:document_extraction, :succeeded)).to be_succeeded
      expect(build(:document_extraction, :failed)).to be_failed
      expect(build(:document_extraction, status: 'pending')).to be_pending
    end
  end

  describe '.latest_first' do
    it 'orders by created_at descending' do
      document = create(:candidate_document)
      older = create(:document_extraction, :failed, candidate_document: document, created_at: 2.days.ago)
      newer = create(:document_extraction, candidate_document: document, status: 'pending', created_at: 1.hour.ago)

      expect(described_class.latest_first.pluck(:id)).to eq([newer.id, older.id])
    end
  end
end
