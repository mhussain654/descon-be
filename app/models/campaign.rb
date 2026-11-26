# frozen_string_literal: true

# A group of candidates handled together -- one import or intake, named by
# date and country (code e.g. "2026-11-26-QATAR"). Staff pick a working campaign
# on their profile and every candidate list, dashboard and report narrows to
# it. The single Test campaign (kind "test") holds test candidates and is left
# out of "All campaigns".
class Campaign < ApplicationRecord
  KINDS = %w[regular test].freeze
  TEST_KIND = 'test'

  belongs_to :country, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :candidate_assignments, inverse_of: :campaign, dependent: :restrict_with_exception

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :code, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 120 }
  validates :kind, inclusion: { in: KINDS }
  validates :country, presence: true, unless: :test?

  scope :active, -> { where(active: true) }
  scope :regular, -> { where(kind: 'regular') }

  def self.test_campaign = find_by(kind: TEST_KIND)

  # "2026-11-26-QATAR", or "2026-11-26-QATAR-2" (-3, ...) when taken.
  def self.next_code(date:, country:)
    base = "#{date.iso8601}-#{country.code.upcase}"
    taken = where('code = :base OR code LIKE :pattern', base:, pattern: "#{sanitize_sql_like(base)}-%").pluck(:code)
    return base unless taken.include?(base)

    suffix = 2
    suffix += 1 while taken.include?("#{base}-#{suffix}")
    "#{base}-#{suffix}"
  end

  def test? = kind == TEST_KIND

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end
