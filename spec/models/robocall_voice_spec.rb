# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RobocallVoice do
  it 'has a valid factory and assigns a public id' do
    voice = create(:robocall_voice)

    expect(voice).to be_persisted
    expect(voice.public_id).to be_present
  end

  it 'strips whitespace and treats blank optional text as absent' do
    voice = create(:robocall_voice, name_en: '  Visa approved ', name_ur: '   ', voice_id: ' 205 ')

    expect(voice).to have_attributes(name_en: 'Visa approved', name_ur: nil, voice_id: '205')
  end

  it 'requires a name and a well-formed voice id' do
    expect(build(:robocall_voice, name_en: '')).not_to be_valid
    expect(build(:robocall_voice, voice_id: '')).not_to be_valid
    ['10 2', '102;drop', 'a' * 33].each do |bad|
      expect(build(:robocall_voice, voice_id: bad)).not_to be_valid, "expected #{bad.inspect} invalid"
    end
  end

  it 'keeps names and voice ids unique, ignoring name case' do
    create(:robocall_voice, name_en: 'Flight', voice_id: '300')

    expect(build(:robocall_voice, name_en: 'FLIGHT')).not_to be_valid
    expect(build(:robocall_voice, voice_id: '300')).not_to be_valid
  end

  it 'lists active voices in name order' do
    flight = create(:robocall_voice, name_en: 'Flight')
    create(:robocall_voice, name_en: 'Old', active: false)
    visa = create(:robocall_voice, name_en: 'Visa')

    expect(described_class.active.ordered).to eq([flight, visa])
  end

  it 'cannot be deleted while a batch uses it' do
    batch = create(:bulk_call_batch)

    expect { batch.robocall_voice.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
