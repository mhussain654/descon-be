# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MobilizationProcesses::Seeder do
  def definition(**overrides)
    { code: 'seeder_spec_process', version: 1, country_code: nil, provisional: true,
      stages: %w[registered documents_pending] }.merge(overrides)
  end

  it 'leaves the already-published approved processes untouched' do
    expect { described_class.call }.not_to change(MobilizationProcessStage, :count)
    expect(described_class.call.map(&:code)).to eq(%w[common_mobilization ksa_mobilization qatar_mobilization])
  end

  it 'creates and publishes a new definition with action types from the catalog mapping' do
    country = create(:country)

    process = described_class.call(definitions: [definition(country_code: country.code, provisional: false)]).sole

    expect(process).to have_attributes(status: 'active', country:, provisional: false)
    expect(process.stages.map { |stage| [stage.position, stage.code, stage.action_type] })
      .to eq([[1, 'registered', 'none'], [2, 'documents_pending', 'document_submission']])
  end

  it 'refuses to accept a published version whose stage settings no longer match its definition' do
    process = described_class.call(definitions: [definition]).sole
    # Published stages are read-only to the app; simulate drift made directly in the database.
    MobilizationProcessStage.where(id: process.stages.last.id).update_all(action_type: 'payment') # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.call(definitions: [definition]) }.to raise_error(described_class::MismatchError)
    expect { described_class.call(definitions: [definition(provisional: false)]) }
      .to raise_error(described_class::MismatchError)
  end

  it 'refuses to treat an edited stage list as the same published version' do
    described_class.call(definitions: [definition])

    expect { described_class.call(definitions: [definition(stages: %w[registered verified])]) }
      .to raise_error(described_class::MismatchError, /seeder_spec_process v1/)
  end
end
