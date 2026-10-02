# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MobilizationProcess, type: :model do
  def stage(code) = WorkflowStage.find_by!(code:)

  def draft_process(code: "test_process_#{SecureRandom.hex(3)}", country: nil, stage_codes: %w[registered verified])
    process = described_class.create!(code:, version: 1, country:)
    stage_codes.each.with_index(1) do |stage_code, position|
      process.stages.create!(workflow_stage: stage(stage_code), position:, action_type: 'none')
    end
    process
  end

  it 'resolves a country to its own active process, otherwise to the common process' do
    expect(described_class.resolve_for(process_country(:qatar)).code).to eq('qatar_mobilization')
    expect(described_class.resolve_for(process_country(:saudi_arabia)).code).to eq('ksa_mobilization')
    expect(described_class.resolve_for(create(:country)).code).to eq('common_mobilization')
    expect(described_class.resolve_for(nil)).to be_common
  end

  it 'publishes a draft and retires the previously active version for the same country' do
    country = create(:country)
    first = draft_process(country:)
    first.publish!
    second = described_class.create!(code: first.code, version: 2, country:)
    second.stages.create!(workflow_stage: stage('registered'), position: 1, action_type: 'none')

    second.publish!(by: create(:user, role: 'admin'))

    expect(first.reload.status).to eq('retired')
    expect(first.effective_until).to be_present
    expect(second.reload).to have_attributes(status: 'active', published_at: be_present)
    expect(described_class.resolve_for(country)).to eq(second)
  end

  it 'refuses to publish a process without stages, or one that is not a draft' do
    empty = described_class.create!(code: 'empty_process', version: 1, country: create(:country))
    expect { empty.publish! }.to raise_error(ActiveRecord::RecordInvalid)

    published = draft_process(country: create(:country))
    published.publish!
    expect { published.publish! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'freezes a published definition: no edits, no new or changed stages, no deletion' do
    process = draft_process(country: create(:country))
    process.publish!

    expect(process.update(provisional: true)).to be(false)
    expect(process.errors[:base]).to be_present
    expect { process.stages.first.update!(action_type: 'payment') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    added = process.stages.build(workflow_stage: stage('documents_pending'), position: 3, action_type: 'none')
    expect(added).not_to be_valid
    expect(process.destroy).to be(false)
    expect(MobilizationProcessStage.new(mobilization_process: process).destroy).to be(false)
  end

  it 'never reactivates a retired version' do
    process = draft_process(country: create(:country))
    process.publish!
    process.retire!

    expect(process.update(status: 'active')).to be(false)
  end

  it 'answers stage lookups within its own sequence only' do
    ksa = described_class.resolve_for(process_country(:saudi_arabia))

    expect(ksa.first_stage.code).to eq('registered')
    expect(ksa.terminal_stage.code).to eq('ticket_handover')
    expect(ksa.next_stage_after(ksa.stage_for(stage('verified'))).code).to eq('campaign_nomination')
    expect(ksa.next_stage_after(ksa.terminal_stage)).to be_nil
    expect(ksa.next_stage_after(nil)).to be_nil
    expect(ksa.stage_for(nil)).to be_nil
    expect(ksa.includes_stage_code?('e_number_received')).to be(true)
    expect(ksa.includes_stage_code?('qvc_appointment_booked')).to be(false)
    expect(ksa.includes_stage_code?('not_a_stage')).to be(false)
  end
end
