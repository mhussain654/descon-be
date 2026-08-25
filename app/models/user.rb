# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :lockable, :validatable

  STAFF_ROLE_CODES = %w[admin hr mps finance management].freeze
  STAFF_STATES = %w[invited active suspended].freeze
  INVITATION_TTL = 72.hours

  belongs_to :staff_role, class_name: 'Role', foreign_key: :role, primary_key: :code, inverse_of: :users, optional: true
  belongs_to :invited_by, class_name: 'User', optional: true

  has_many :sessions, dependent: :destroy
  has_many :created_candidates, class_name: 'Candidate', foreign_key: :created_by_id, inverse_of: :created_by,
                                dependent: :restrict_with_exception
  has_many :created_candidate_assignments, class_name: 'CandidateAssignment', foreign_key: :created_by_id,
                                           inverse_of: :created_by, dependent: :restrict_with_exception

  has_many :uploaded_candidate_documents, class_name: 'CandidateDocument', foreign_key: :uploaded_by_id,
                                          inverse_of: :uploaded_by, dependent: :nullify
  has_many :verified_candidate_documents, class_name: 'CandidateDocument', foreign_key: :verified_by_id,
                                          inverse_of: :verified_by, dependent: :nullify
  has_many :recorded_payments, class_name: 'Payment', foreign_key: :recorded_by_id, inverse_of: :recorded_by,
                               dependent: :nullify
  has_many :initiated_communications, class_name: 'Communication', foreign_key: :initiated_by_id,
                                      inverse_of: :initiated_by, dependent: :nullify
  has_many :acted_stage_histories, class_name: 'CandidateStageHistory', foreign_key: :actor_id, inverse_of: :actor,
                                   dependent: :nullify
  has_many :audit_events, foreign_key: :actor_id, inverse_of: :actor, dependent: :nullify

  before_validation :assign_public_id, on: :create
  before_validation :normalize_email
  before_validation :normalize_staff_state
  before_validation :synchronize_active_and_staff_state

  validates :active, inclusion: { in: [true, false] }
  validates :public_id, presence: true, uniqueness: true
  validates :email, uniqueness: { case_sensitive: false }
  validates :role, presence: true, inclusion: { in: STAFF_ROLE_CODES }
  validates :staff_state, presence: true, inclusion: { in: STAFF_STATES }

  delegate :permissions, to: :staff_role

  def self.normalize_email_value(email) = email.to_s.strip.downcase

  def active_for_authentication?
    super && active_staff_account?
  end

  def admin? = role?('admin')

  def staff? = STAFF_ROLE_CODES.include?(role)

  def authorization_active?
    active_staff_account? && active_staff_role?
  end

  def invited? = staff_state == 'invited'

  def active_staff_account? = staff_state == 'active'

  def suspended? = staff_state == 'suspended'

  def hr? = role?('hr')

  def mps? = role?('mps')

  def finance? = role?('finance')

  def management? = role?('management')

  def permission?(permission_code)
    authorization_active? && permissions.where(active: true).exists?(code: permission_code.to_s)
  end

  def effective_permission_codes
    return [] unless authorization_active?

    permissions.where(active: true).distinct.order(:code).pluck(:code)
  end

  def invitation_active?
    invited? && invitation_token_digest.present? && invitation_expires_at.present? && invitation_expires_at.future?
  end

  private

  def active_staff_role? = staff? && staff_role&.active?

  def password_required?
    return false if invited? && encrypted_password.blank?

    super
  end

  def role?(role_code) = role == role_code

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_email
    self.email = self.class.normalize_email_value(email)
  end

  def normalize_staff_state
    self.staff_state = staff_state.to_s.strip.downcase.presence || 'active'
  end

  def synchronize_active_and_staff_state
    return self.active = active_staff_account? if will_save_change_to_staff_state? || !will_save_change_to_active?

    self.staff_state = active? ? 'active' : 'suspended'
  end
end
