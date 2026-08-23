# frozen_string_literal: true

class CandidateStageHistory < ApplicationRecord
  include ImmutableRecord

  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :candidate_assignment
  belongs_to :workflow_stage
  belongs_to :actor, class_name: 'User', optional: true

  validates :occurred_at, presence: true
  validates :reason_code, format: { with: CODE_FORMAT }, allow_blank: true
end
