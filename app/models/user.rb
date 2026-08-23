# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :lockable, :validatable

  belongs_to :staff_role, class_name: 'Role', foreign_key: :role, primary_key: :code, inverse_of: :users

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

  validates :active, inclusion: { in: [true, false] }
  validates :public_id, presence: true, uniqueness: true
  validates :role, presence: true

  delegate :permissions, to: :staff_role

  def active_for_authentication?
    super && active?
  end

  def admin?
    role == 'admin'
  end

  def staff?
    role == 'staff'
  end

  def permission?(permission_code)
    permissions.exists?(code: permission_code.to_s)
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
