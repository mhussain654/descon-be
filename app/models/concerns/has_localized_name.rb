# frozen_string_literal: true

module HasLocalizedName
  extend ActiveSupport::Concern

  def name_for(locale: I18n.locale)
    localized_name_from_i18n(locale) || localized_name_from_columns(locale)
  end

  private

  def localized_name_from_i18n(locale)
    return unless respond_to?(:code)
    return unless self.class.respond_to?(:i18n_name_scope)

    I18n.with_locale(locale) do
      I18n.t("#{self.class.i18n_name_scope}.#{code}", default: nil)
    end
  end

  def localized_name_from_columns(locale)
    localized_locale = locale.to_sym
    return name_ur if localized_locale == :ur && respond_to?(:name_ur)

    name_en if respond_to?(:name_en)
  end
end
