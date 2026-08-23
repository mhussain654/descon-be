# frozen_string_literal: true

RSpec.shared_examples 'a localized reference model' do
  it 'returns the Urdu name when requested' do
    expect(record.name_for(locale: :ur)).to eq(expected_urdu_name)
  end

  it 'returns the English name by default' do
    expect(record.name_for).to eq(expected_english_name)
  end
end
