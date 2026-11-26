# frozen_string_literal: true

module Admin
  module Campaigns
    # Creates a regular campaign for a country, coded by date and country
    # ("2026-11-26-QATAR", suffixed when taken). The name defaults to
    # "<date> <country>" and staff may give their own.
    class CreateService < ApplicationService
      def initialize(actor:, country_code:, name: nil, start_date: nil)
        @actor = actor
        @country_code = country_code
        @name = name.to_s.strip.presence
        @start_date = start_date
      end

      def call
        country = ::Country.active.find_by(code: @country_code.to_s.strip.downcase)
        unless country
          raise ValidationError.new(field: 'campaign.country_code',
                                    message: I18n.t('api.errors.unknown_country_code'))
        end

        date = parsed_date
        ::Campaign.create!(
          code: ::Campaign.next_code(date:, country:), name: @name || "#{date.iso8601} #{country.name_en}",
          kind: 'regular', country:, created_by: @actor
        )
      end

      private

      def parsed_date
        return Date.current if @start_date.blank?

        Date.iso8601(@start_date.to_s)
      rescue Date::Error
        raise ValidationError.new(field: 'campaign.start_date', message: I18n.t('api.errors.validation_failed'))
      end
    end
  end
end
