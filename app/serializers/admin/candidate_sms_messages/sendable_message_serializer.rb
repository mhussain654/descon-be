# frozen_string_literal: true

module Admin
  module CandidateSmsMessages
    # One message staff can send this candidate: the languages it has a
    # template for, the values its template uses, and those values filled in
    # from the candidate's record where the record has them (per language,
    # since a country name differs).
    class SendableMessageSerializer
      def initialize(template, candidate:)
        @template = template
        @candidate = candidate
      end

      def as_json(*)
        {
          message_code: @template.message_code,
          automatic: @template.enabled,
          locales: CandidateSmsDelivery::LOCALES.select { |locale| @template.template_id_for(locale).present? },
          variables: @template.variables,
          prefilled: CandidateSmsDelivery::LOCALES.index_with { |locale| prefilled(locale) }
        }
      end

      private

      def prefilled(locale)
        assignment = @candidate.current_assignment
        known = { 'name' => @candidate.full_name }
        known['country'] = ::CandidateSms::ScheduleDelivery.country_name(assignment, locale) if assignment&.country
        known.slice(*@template.variables)
      end
    end
  end
end
