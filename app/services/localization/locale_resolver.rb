# frozen_string_literal: true

module Localization
  class LocaleResolver < ApplicationService
    def initialize(explicit_locale:, accept_language:)
      @explicit_locale = explicit_locale
      @accept_language = accept_language
    end

    def call
      normalize_locale(@explicit_locale) ||
        accepted_locales.find { |locale| supported_locale?(locale) } ||
        I18n.default_locale
    end

    private

    def accepted_locales
      locales_with_quality = @accept_language.to_s.split(',').filter_map do |value|
        locale, quality = value.split(';').map(&:strip)
        normalized_locale = normalize_locale(locale)
        next unless normalized_locale

        parsed_quality = parse_quality(quality)
        next unless parsed_quality

        [normalized_locale, parsed_quality]
      end

      locales_with_quality.sort_by { |_locale, quality| -quality }.map(&:first)
    end

    def normalize_locale(value)
      normalized = value.to_s.strip.tr('-', '_').downcase
      return if normalized.blank?
      return I18n.default_locale if normalized == '*'

      locale = normalized.to_sym
      return locale if supported_locale?(locale)

      base_locale = normalized.split('_').first.to_sym
      base_locale if supported_locale?(base_locale)
    end

    def supported_locale?(locale)
      Rails.configuration.x.i18n.supported_locales.include?(locale)
    end

    def parse_quality(value)
      return 1.0 if value.blank?

      return unless value.start_with?('q=')

      quality = Float(value.delete_prefix('q='), exception: false)
      return unless quality&.between?(0.0, 1.0)
      return if quality.zero?

      quality
    end
  end
end
