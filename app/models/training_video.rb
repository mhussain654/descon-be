# frozen_string_literal: true

class TrainingVideo < ApplicationRecord
  MAX_BYTES = 250.megabytes
  TYPES = %w[video/mp4].freeze

  belongs_to :created_by, class_name: 'User'
  has_one_attached :file

  validates :title_en, :title_ur, presence: true, length: { maximum: 150 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :valid_file

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :id) }

  private

  def valid_file
    return errors.add(:file, :blank) unless file.attached?

    errors.add(:file, :invalid) unless TYPES.include?(file.blob.content_type)
    errors.add(:file, :too_long) if file.blob.byte_size > MAX_BYTES
  end
end
