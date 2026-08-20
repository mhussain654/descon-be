# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Localization::LocaleResolver do
  describe '.call' do
    it 'prefers X-Locale over Accept-Language when both are supported' do
      locale = described_class.call(explicit_locale: 'ur', accept_language: 'en-GB,en;q=0.8')

      expect(locale).to eq(:ur)
    end

    it 'uses Accept-Language when X-Locale is unsupported' do
      locale = described_class.call(explicit_locale: 'fr', accept_language: 'ur-PK,ur;q=0.9,en;q=0.8')

      expect(locale).to eq(:ur)
    end

    it 'respects Accept-Language quality weights' do
      locale = described_class.call(explicit_locale: nil, accept_language: 'en;q=0.5,ur;q=0.9')

      expect(locale).to eq(:ur)
    end

    it 'falls back to the default locale when no supported locale is requested' do
      locale = described_class.call(explicit_locale: nil, accept_language: nil)

      expect(locale).to eq(:en)
    end

    it 'falls back to English when a locale is missing a translation key' do
      translation = I18n.with_locale(:ur) { I18n.t('api.messages.fallback_example') }

      expect(translation).to eq('English fallback message.')
    end

    it 'keeps request locales isolated across concurrent threads' do
      queue = Queue.new

      threads = [
        Thread.new do
          I18n.with_locale(described_class.call(explicit_locale: 'ur', accept_language: nil)) do
            2.times { queue << [I18n.locale, I18n.t('api.errors.unauthorized')] }
          end
        end,
        Thread.new do
          I18n.with_locale(described_class.call(explicit_locale: 'en', accept_language: nil)) do
            2.times { queue << [I18n.locale, I18n.t('api.errors.unauthorized')] }
          end
        end
      ]

      threads.each(&:join)
      results = Array.new(4) { queue.pop }

      expect(results.count([:ur, 'درست اسناد فراہم نہیں کی گئیں۔'])).to eq(2)
      expect(results.count([:en, 'Invalid credentials.'])).to eq(2)
      expect(I18n.locale).to eq(I18n.default_locale)
    end
  end
end
