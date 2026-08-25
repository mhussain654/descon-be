# frozen_string_literal: true

class AuthenticationEvent < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :user, optional: true
  belongs_to :session, optional: true

  validates :event_code, presence: true, format: { with: CODE_FORMAT }
  validates :occurred_at, presence: true
  validates :metadata, exclusion: { in: [nil] }
end
