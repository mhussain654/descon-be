# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    class StateResolver < ApplicationService
      def initialize(assignment:, blocking_requirements:, can_submit:, required_documents:, required_requirements:)
        @assignment = assignment
        @blocking_requirements = blocking_requirements
        @can_submit = can_submit
        @required_documents = required_documents
        @required_requirements = required_requirements
      end

      def call
        ordered_states.each do |state, predicate|
          return state if send(predicate)
        end

        'incomplete'
      end

      private

      def blocking_reason?(reason)
        @blocking_requirements.any? { |requirement| requirement.reason == reason }
      end

      def ready?
        @can_submit
      end

      def changes_required?
        blocking_reason?('rejected')
      end

      def incomplete?
        blocking_reason?('missing')
      end

      def no_assignment?
        @assignment.blank?
      end

      def no_requirements?
        @required_requirements.empty?
      end

      def ordered_states
        [
          ['no_assignment', :no_assignment?],
          ['no_requirements', :no_requirements?],
          ['changes_required', :changes_required?],
          ['incomplete', :incomplete?],
          ['verified', :verified?],
          ['ready', :ready?],
          ['partially_verified', :partially_verified?],
          ['submitted', :submitted?]
        ]
      end

      def partially_verified?
        statuses.exclude?('uploaded') && statuses.include?('pending_review') && statuses.include?('verified')
      end

      def statuses
        @statuses ||= @required_documents.filter_map(&:api_status)
      end

      def submitted?
        statuses.exclude?('uploaded') &&
          statuses.all? { |status| %w[pending_review verified].include?(status) } &&
          statuses.include?('pending_review')
      end

      def verified?
        @required_documents.all? { |document| document&.api_status == 'verified' }
      end
    end
  end
end
