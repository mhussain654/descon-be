# frozen_string_literal: true

# One checklist configuration row: whether a document type is required,
# optional or not applicable for a scope (common when every scope column is
# nil; otherwise a country, optionally narrowed by project and/or craft),
# plus how the candidate must upload it. The most specific matching row wins
# (Candidates::Documents::RequirementResolver); a winning `not_applicable`
# row removes a document a broader row would otherwise add.
#
# `driver_only` rows apply only to assignments whose craft is a driver craft
# (Craft#is_driver), so e.g. the Qatar driving licence never reaches
# non-drivers. `active` is only "is this configuration row enabled" -- never
# country applicability.
class DocumentRequirement < ApplicationRecord
  REQUIREMENT_LEVELS = %w[required optional not_applicable].freeze
  CONTENT_TYPES = %w[application/pdf image/jpeg image/png].freeze

  belongs_to :document_type
  belongs_to :country, optional: true
  belongs_to :project, optional: true
  belongs_to :craft, optional: true

  validates :document_type_id,
            uniqueness: {
              scope: %i[country_id project_id craft_id],
              message: :taken
            }
  validates :requirement_level, inclusion: { in: REQUIREMENT_LEVELS }
  validates :active, :driver_only, :combined_pdf_allowed, inclusion: { in: [true, false] }
  validates :display_position, numericality: { only_integer: true }
  validates :minimum_files, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :maximum_files, numericality: { only_integer: true, greater_than_or_equal_to: :minimum_files }
  validates :maximum_file_size, numericality: { only_integer: true, greater_than: 0 }
  validate :side_codes_are_known
  validate :content_types_are_supported

  # Kept under the old boolean column's name, which callers across the app read.
  def required = requirement_level == 'required' # rubocop:disable Naming/PredicateMethod
  alias required? required

  # Convenience for the common required/optional case (seeds, specs).
  def required=(value)
    self.requirement_level = ActiveModel::Type::Boolean.new.cast(value) ? 'required' : 'optional'
  end

  def not_applicable? = requirement_level == 'not_applicable'

  # The label an unlabelled file gets when only one reading makes sense: the
  # single repeatable label (certificates), or `combined` for a lone file
  # where a combined PDF is allowed (the legacy single-`file` upload).
  def default_side_code(file_count:)
    codes = Array(allowed_side_codes)
    return codes.first if codes.size == 1
    return 'combined' if file_count == 1 && combined_pdf_allowed && codes.include?('combined')

    nil
  end

  def instructions_for(locale: I18n.locale)
    locale.to_s == 'ur' ? instructions_ur.presence || instructions_en : instructions_en.presence || instructions_ur
  end

  private

  def side_codes_are_known
    unknown = Array(allowed_side_codes) - CandidateDocumentFile::SIDE_CODES
    errors.add(:allowed_side_codes, :inclusion) if unknown.any?
    errors.add(:combined_pdf_allowed, :invalid) if combined_pdf_allowed && allowed_side_codes.present? &&
                                                   allowed_side_codes.exclude?('combined')
  end

  def content_types_are_supported
    types = Array(accepted_content_types)
    errors.add(:accepted_content_types, :inclusion) if types.empty? || (types - CONTENT_TYPES).any?
  end
end
