# frozen_string_literal: true

class CandidateImportBatch < ApplicationRecord
  STATUSES = %w[preflighted committed invalidated].freeze

  belongs_to :actor, class_name: 'User'

  encrypts :preflight_payload

  before_validation :assign_public_id, on: :create

  validates :public_id, :token_digest, :source_filename, :file_fingerprint, :template_version, :expires_at,
            presence: true
  validates :public_id, :token_digest, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  def expired? = expires_at <= Time.current
  def preflighted? = status == 'preflighted'
  def committed? = status == 'committed'

  def rows
    JSON.parse(preflight_payload).fetch('rows')
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end
