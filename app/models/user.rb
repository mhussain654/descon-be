# frozen_string_literal: true

# A staff account (admin, HR, MPS, finance, or management) that authenticates via Devise and
# acts on candidates, documents, payments, workflow, and communications, gated by its role's
# permissions and its own invited/active/suspended lifecycle state.
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
  has_many :verified_candidate_bank_details, class_name: 'CandidateBankDetail', foreign_key: :reviewed_by_id,
                                             inverse_of: :reviewed_by, dependent: :nullify
  has_many :verified_candidate_documents, class_name: 'CandidateDocument', foreign_key: :verified_by_id,
                                          inverse_of: :verified_by, dependent: :nullify
  has_many :recorded_payments, class_name: 'Payment', foreign_key: :recorded_by_id, inverse_of: :recorded_by,
                               dependent: :nullify
  has_many :initiated_communications, class_name: 'Communication', foreign_key: :initiated_by_id,
                                      inverse_of: :initiated_by, dependent: :nullify
  # :nullify, not :restrict_with_exception -- CandidateAiCall is a mutable
  # header row, not itself an audit trail (that's CandidateAiCallEvent,
  # which has its own immutable, separately-attributed `actor` reference).
  has_many :triggered_ai_calls, class_name: 'CandidateAiCall', foreign_key: :triggered_by_id,
                                inverse_of: :triggered_by, dependent: :nullify
  has_many :reviewed_ai_calls, class_name: 'CandidateAiCall', foreign_key: :reviewed_by_id,
                               inverse_of: :reviewed_by, dependent: :nullify
  # :restrict_with_exception, not :nullify -- both associations are
  # ImmutableRecord (append-only). :nullify is a bulk UPDATE that never
  # instantiates the child records, so it would silently bypass
  # ImmutableRecord's before_update guard and erase audit-trail attribution.
  has_many :acted_stage_histories, class_name: 'CandidateStageHistory', foreign_key: :actor_id, inverse_of: :actor,
                                   dependent: :restrict_with_exception
  has_many :audit_events, foreign_key: :actor_id, inverse_of: :actor, dependent: :restrict_with_exception
  has_many :candidate_ai_call_events, foreign_key: :actor_id, inverse_of: :actor, dependent: :restrict_with_exception

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

  # Normalizes an email address for comparison/storage: trims whitespace and lowercases it.
  def self.normalize_email_value(email) = email.to_s.strip.downcase

  # Devise hook: on top of the default checks, also requires the staff account to be active
  # (not invited/suspended) before sign-in is allowed.
  def active_for_authentication?
    super && active_staff_account?
  end

  # True if this user's role is admin.
  def admin? = role?('admin')

  # True if this user's role is one of the recognized staff role codes.
  def staff? = STAFF_ROLE_CODES.include?(role)

  # True if this user is allowed to act at all: their staff account is active and their
  # assigned staff role is itself active (not disabled by an admin).
  def authorization_active?
    active_staff_account? && active_staff_role?
  end

  # True if this user has been invited but hasn't yet activated their account.
  def invited? = staff_state == 'invited'

  # True if this user's staff account is active.
  def active_staff_account? = staff_state == 'active'

  # True if this user's staff account has been suspended.
  def suspended? = staff_state == 'suspended'

  # True if this user's role is hr.
  def hr? = role?('hr')

  # True if this user's role is mps.
  def mps? = role?('mps')

  # True if this user's role is finance.
  def finance? = role?('finance')

  # True if this user's role is management.
  def management? = role?('management')

  # True if the user is authorized overall and their role has the given permission code active.
  def permission?(permission_code)
    authorization_active? && permissions.where(active: true).exists?(code: permission_code.to_s)
  end

  # The sorted list of active permission codes granted to this user via their role, or an
  # empty list if the user isn't currently authorized.
  def effective_permission_codes
    return [] unless authorization_active?

    permissions.where(active: true).distinct.order(:code).pluck(:code)
  end

  # True if this user has a pending invitation that hasn't expired yet.
  def invitation_active?
    invited? && invitation_token_digest.present? && invitation_expires_at.present? && invitation_expires_at.future?
  end

  private

  # True if this user has a staff role assigned and that role itself is active.
  def active_staff_role? = staff? && staff_role&.active?

  # Devise hook: skips the password-required check for invited users who haven't set a
  # password yet, otherwise defers to Devise's default behavior.
  def password_required?
    return false if invited? && encrypted_password.blank?

    super
  end

  # True if this user's role column matches the given role code.
  def role?(role_code) = role == role_code

  # Callback: assigns a public-facing UUID identifier when the user is first created.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Callback: normalizes the email address before validation.
  def normalize_email
    self.email = self.class.normalize_email_value(email)
  end

  # Callback: normalizes the staff_state string, defaulting to 'active' if blank.
  def normalize_staff_state
    self.staff_state = staff_state.to_s.strip.downcase.presence || 'active'
  end

  # Callback: keeps the `active` boolean and `staff_state` string in sync with each other,
  # preferring whichever one was actually changed on this save.
  def synchronize_active_and_staff_state
    return self.active = active_staff_account? if will_save_change_to_staff_state? || !will_save_change_to_active?

    self.staff_state = active? ? 'active' : 'suspended'
  end
end
