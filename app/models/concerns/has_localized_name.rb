# frozen_string_literal: true

# Concern for reference-data models (countries, crafts, roles, etc.) that need a display name
# in the caller's locale, preferring an I18n translation keyed by the record's code and falling
# back to the record's own name_en/name_ur columns.
module HasLocalizedName
  extend ActiveSupport::Concern

  # The display name for this record in the given locale (defaults to the current I18n locale).
  def name_for(locale: I18n.locale)
    localized_name_from_i18n(locale) || localized_name_from_columns(locale)
  end

  private

  # Looks up a translated name from the locale files, keyed by the model's i18n_name_scope and
  # this record's code; returns nil if the model doesn't support this lookup or no key is found.
  def localized_name_from_i18n(locale)
    return unless respond_to?(:code)
    return unless self.class.respond_to?(:i18n_name_scope)

    I18n.with_locale(locale) do
      I18n.t("#{self.class.i18n_name_scope}.#{code}", default: nil)
    end
  end

  # Falls back to the record's own name_ur or name_en column depending on the requested locale.
  def localized_name_from_columns(locale)
    localized_locale = locale.to_sym
    return name_ur if localized_locale == :ur && respond_to?(:name_ur)

    name_en if respond_to?(:name_en)
  end
end
