# frozen_string_literal: true

# One named call type ("Visa approved", "Flight") an admin can pick for a bulk
# call: a label plus the RoboCall voice id that is played. Never deleted --
# switch `active` off to retire one (batches keep their own snapshot).
class RobocallVoice < ApplicationRecord
  VOICE_ID_FORMAT = /\A[A-Za-z0-9_-]{1,32}\z/

  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  has_many :bulk_call_batches, dependent: :restrict_with_exception

  before_validation :assign_public_id, on: :create
  before_validation :normalize_fields

  validates :public_id, presence: true, uniqueness: true
  validates :name_en, presence: true, uniqueness: { case_sensitive: false }
  validates :voice_id, presence: true, uniqueness: true, format: { with: VOICE_ID_FORMAT }
  validates :active, inclusion: { in: [true, false] }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name_en) }

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_fields
    %i[name_en name_ur voice_id].each { |attribute| self[attribute] = self[attribute].to_s.strip.presence }
  end
end
