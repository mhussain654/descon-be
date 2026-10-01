# frozen_string_literal: true

# The single admin-editable row pointing candidates at the one external link
# (e.g. a YouTube channel/playlist) where all training documents and videos
# live -- content is managed entirely off-platform; this app only stores and
# serves the link. `singleton_guard` is always true; its unique index makes a
# second row impossible at the database level (see the migration), not just
# by convention -- #current is the only supported way to obtain the row.
class TrainingSetting < ApplicationRecord
  # [PLACEHOLDER -- NOT CLIENT-APPROVED] Seeded so the candidate Training
  # page and the admin settings screen are never empty before the client
  # provides their real training link; change via the admin UI, not by
  # editing this constant.
  DEFAULT_URL = 'https://www.youtube.com/@DesconManpower'

  belongs_to :updated_by, class_name: 'User', optional: true

  validates :singleton_guard, inclusion: { in: [true] }
  validates :url, presence: true
  validate :url_is_http_or_https

  before_destroy :raise_readonly_record

  # Returns the singleton row, creating it (with the placeholder default
  # link) if this is the first access anywhere -- e.g. a freshly
  # schema-loaded test database, which never replays a migration's data.
  # Race-safe: a concurrent first access loses the unique-index race and
  # simply reads back the winner's row instead.
  def self.current
    first || create!(singleton_guard: true, url: DEFAULT_URL)
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  private

  def url_is_http_or_https
    return if url.blank?

    uri = URI.parse(url)
    errors.add(:url, :invalid) unless uri.is_a?(URI::HTTP) # URI::HTTPS < URI::HTTP, so this covers both
  rescue URI::InvalidURIError
    errors.add(:url, :invalid)
  end

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is a singleton and cannot be destroyed"
  end
end
