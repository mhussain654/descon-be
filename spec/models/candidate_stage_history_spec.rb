# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateStageHistory, type: :model do
  subject(:candidate_stage_history) { build(:candidate_stage_history) }

  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:workflow_stage) }
  it { is_expected.to belong_to(:actor).class_name('User').optional }

  it 'is immutable after creation' do
    stage_history = create(:candidate_stage_history)

    expect { stage_history.update!(note: 'Changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { stage_history.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
