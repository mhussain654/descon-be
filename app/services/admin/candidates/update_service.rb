# frozen_string_literal: true

module Admin
  module Candidates
    # Updates a candidate's own profile fields and, only before any document
    # has actually been uploaded, its project/country/craft. CNIC (the
    # candidate's own login identifier) and reference_number (used as an
    # external tracking identifier elsewhere) are never editable through this
    # endpoint -- both are treated as immutable once assigned.
    #
    # Document requirements are resolved *live* from the assignment's
    # project/country/craft on every read (Candidates::Documents::
    # RequirementResolver), never frozen at a point in time -- so changing
    # them is only actually risky once a document has been uploaded against
    # the old requirement set. `registered` (position 1) auto-advances to
    # `documents_pending` (position 2) immediately on creation
    # (CandidateWorkflows::AutomaticTransitionService), so locking this
    # purely to `registered` would make the fields practically uneditable in
    # real use; the true safe boundary is "no document uploaded yet," i.e.
    # position <= DOCUMENTS_PENDING_POSITION.
    #
    # `expected_updated_at`, when supplied, must match the current combined
    # candidate/assignment state (the more recent of the two `updated_at`
    # values) or the update is rejected as stale -- the same
    # someone-changed-this-first protection the workflow feature gives
    # transitions via `expected_current_stage_code`, adapted here since a
    # profile edit is a plain attribute update, not a stage transition.
    # rubocop:disable Metrics/ClassLength
    class UpdateService < ApplicationService
      DOCUMENTS_PENDING_POSITION = 2

      # Shared with Admin::CandidateSerializer, which exposes this same
      # boolean to the frontend as `assignment.fields_editable` -- the single
      # source of truth for the lock boundary, so the frontend never has to
      # duplicate this business rule to decide whether to render the
      # project/country/craft fields as read-only.
      def self.assignment_fields_editable?(assignment)
        assignment.present? && assignment.current_workflow_stage.position <= DOCUMENTS_PENDING_POSITION
      end

      # Symbols, not strings -- `@provided_fields` comes from a
      # double-splatted keyword-argument hash, whose keys are always symbols.
      ASSIGNMENT_FIELD_CODES = %i[country_code project_code craft_code].freeze

      Params = Struct.new(
        :actor, :candidate, :full_name, :mobile_number, :passport_number, :preferred_locale,
        :next_of_kin_name, :next_of_kin_relationship, :next_of_kin_mobile_number, :next_of_kin_cnic,
        :country_code, :project_code, :craft_code, :expected_updated_at,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(**params)
        # Not `.compact`'d -- a key's mere *presence* in the request payload
        # means the client intends to set it (including to blank, which
        # `validate_passport_number!` treats as "clear it"), distinct from a
        # key the client never sent at all (a real partial-update PATCH body
        # only includes fields actually being changed).
        @provided_fields = params.except(:actor, :candidate, :expected_updated_at).keys
      end

      def call
        validate_actor!
        validate_staleness!
        validate_payload!

        CandidateAssignment.transaction do
          update_candidate!
          update_assignment! if assignment_fields_provided?
          record_audit!
        end

        @params.candidate.reload
      end

      private

      def assignment
        @assignment ||= @params.candidate.current_assignment
      end

      def combined_updated_at
        [@params.candidate.updated_at, assignment&.updated_at].compact.max
      end

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_candidates')
      end

      def validate_staleness!
        return if @params.expected_updated_at.blank?

        expected = Time.iso8601(@params.expected_updated_at.to_s)
        raise StaleCandidateError unless expected.to_i == combined_updated_at&.to_i
      rescue ArgumentError
        raise ValidationError.new(field: 'expected_updated_at', message: I18n.t('api.errors.validation_failed'))
      end

      def validate_payload!
        validate_full_name! if @provided_fields.include?(:full_name)
        validate_mobile_number! if @provided_fields.include?(:mobile_number)
        validate_passport_number! if @provided_fields.include?(:passport_number)
        validate_preferred_locale! if @provided_fields.include?(:preferred_locale)
        validate_next_of_kin! if next_of_kin_fields_provided?
        validate_assignment_fields! if assignment_fields_provided?
      end

      def assignment_fields_provided?
        @provided_fields.intersect?(ASSIGNMENT_FIELD_CODES)
      end

      def next_of_kin_fields_provided?
        @provided_fields.intersect?(next_of_kin_fields)
      end

      def next_of_kin_fields
        %i[next_of_kin_name next_of_kin_relationship next_of_kin_mobile_number next_of_kin_cnic]
      end

      def validate_next_of_kin!
        values = next_of_kin_fields.index_with { |field| next_of_kin_value(field) }
        return if values.values.all?(&:blank?)

        validate_next_of_kin_presence!(values)
        validate_next_of_kin_mobile_number!(values.fetch(:next_of_kin_mobile_number))
        return if values.fetch(:next_of_kin_cnic).match?(Candidate::CNIC_FORMAT)

        raise_validation_error('next_of_kin_cnic', 'api.errors.next_of_kin_cnic_invalid')
      end

      def validate_next_of_kin_presence!(values)
        values.each do |field, value|
          raise_validation_error(field.to_s, 'api.errors.next_of_kin_field_required') if value.blank?
        end
      end

      def validate_next_of_kin_mobile_number!(value)
        return if value.match?(Candidate::MOBILE_NUMBER_FORMAT)

        raise_validation_error('next_of_kin_mobile_number', 'api.errors.next_of_kin_mobile_number_invalid')
      end

      def next_of_kin_value(field)
        raw_value = provided?(field) ? @params.public_send(field) : @params.candidate.public_send(field)
        return normalized_mobile_number(raw_value).presence if field == :next_of_kin_mobile_number
        return ::Candidates::CnicNormalizer.call(raw_value).presence if field == :next_of_kin_cnic

        raw_value.to_s.strip.presence
      end

      def validate_full_name!
        return if @params.full_name.to_s.strip.present?

        raise_validation_error('full_name', 'api.errors.candidate_full_name_required')
      end

      def validate_mobile_number!
        value = normalized_mobile_number(@params.mobile_number)
        unless value.match?(Candidate::MOBILE_NUMBER_FORMAT)
          raise_validation_error('mobile_number', 'api.errors.candidate_mobile_number_invalid')
        end
        raise DuplicateMobileNumberError if other_candidate_has_mobile_number?(value)
      end

      def other_candidate_has_mobile_number?(value)
        Candidate.where(mobile_number: value).where.not(id: @params.candidate.id).exists?
      end

      def validate_passport_number!
        value = normalized_passport_number(@params.passport_number)
        return if value.blank?

        unless value.match?(Candidate::PASSPORT_NUMBER_FORMAT)
          raise_validation_error('passport_number', 'api.errors.candidate_passport_number_invalid')
        end
        raise DuplicatePassportNumberError if other_candidate_has_passport?(value)
      end

      def other_candidate_has_passport?(value)
        Candidate.where(passport_number: value).where.not(id: @params.candidate.id).exists?
      end

      def validate_preferred_locale!
        value = @params.preferred_locale.to_s.strip.downcase
        return if Candidate::PREFERRED_LOCALES.include?(value)

        raise_validation_error('preferred_locale', 'api.errors.candidate_preferred_locale_invalid')
      end

      def validate_assignment_fields!
        raise_locked_error(locked_field_name) unless assignment_fields_editable?

        @country = validated_reference(Country, @params.country_code, field: 'country_code') if provided?(:country_code)
        @project = validated_reference(Project, @params.project_code, field: 'project_code') if provided?(:project_code)
        @craft = validated_reference(Craft, @params.craft_code, field: 'craft_code') if provided?(:craft_code)
      end

      def provided?(field) = @provided_fields.include?(field)

      def locked_field_name
        (@provided_fields & ASSIGNMENT_FIELD_CODES).first.to_s
      end

      def assignment_fields_editable?
        self.class.assignment_fields_editable?(assignment)
      end

      def raise_locked_error(field)
        raise CandidateAssignmentFieldLockedError.new(field:)
      end

      def validated_reference(model, code, field:)
        record = model.active.find_by(code: code.to_s.strip.downcase)
        return record if record.present?

        raise_validation_error(field, "api.errors.unknown_#{field}")
      end

      def raise_validation_error(field, translation_key)
        raise ValidationError.new(field:, message: I18n.t(translation_key))
      end

      def update_candidate!
        attributes = candidate_attributes
        return if attributes.empty?

        @params.candidate.update!(attributes)
      end

      def candidate_attributes
        {
          full_name: @params.full_name.to_s.strip,
          mobile_number: normalized_mobile_number(@params.mobile_number),
          passport_number: normalized_passport_number(@params.passport_number),
          preferred_locale: @params.preferred_locale.to_s.strip.downcase,
          next_of_kin_name: next_of_kin_value(:next_of_kin_name),
          next_of_kin_relationship: next_of_kin_value(:next_of_kin_relationship),
          next_of_kin_mobile_number: next_of_kin_value(:next_of_kin_mobile_number),
          next_of_kin_cnic: next_of_kin_value(:next_of_kin_cnic)
        }.slice(*@provided_fields)
      end

      def update_assignment!
        attributes = assignment_attributes
        return if attributes.empty?

        assignment.update!(attributes)
      end

      def assignment_attributes
        { country_code: @country, project_code: @project, craft_code: @craft }
          .slice(*@provided_fields)
          .transform_keys { |field| field.to_s.delete_suffix('_code').to_sym }
      end

      def normalized_mobile_number(raw_value)
        value = raw_value.to_s.strip
        digits = value.gsub(/\D/, '')
        value.start_with?('+') ? "+#{digits}" : digits
      end

      def normalized_passport_number(raw_value)
        raw_value.to_s.upcase.gsub(/\s+/, '').presence
      end

      def record_audit!
        ::Admin::Candidates::AuditRecorder.call(
          actor: @params.actor,
          candidate: @params.candidate,
          action_code: 'candidate_updated',
          changed_fields: @provided_fields.map(&:to_s)
        )
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
