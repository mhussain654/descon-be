# frozen_string_literal: true

module Admin
  module Candidates
    # Creates a single candidate + its initial assignment from the admin
    # candidate-creation form (MPS-F301) -- source_code is always 'admin_ui',
    # distinguishing these from bulk 'csv_import' rows (Admin::Candidates::ImportService).
    # Always starts at the 'registered' stage; unlike CSV import, this form
    # never lets staff pick an arbitrary starting stage or active/status
    # override, since a freshly created candidate has no history to seed.
    # rubocop:disable Metrics/ClassLength
    class CreateService < ApplicationService
      AUDITED_FIELDS = %w[
        full_name cnic mobile_number passport_number preferred_locale
        next_of_kin_name next_of_kin_relationship next_of_kin_mobile_number next_of_kin_cnic
        country_code project_code craft_code reference_number
      ].freeze

      Params = Struct.new(
        :actor, :full_name, :cnic, :mobile_number, :passport_number, :preferred_locale,
        :next_of_kin_name, :next_of_kin_relationship, :next_of_kin_mobile_number, :next_of_kin_cnic,
        :country_code, :project_code, :craft_code, :reference_number, :request_id,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(**params, **normalized_attributes(params))
      end

      def call
        validate_actor!
        validate_payload!

        CandidateAssignment.transaction { perform_creation }
      rescue ActiveRecord::RecordNotUnique
        raise ValidationError.new(message: I18n.t('api.errors.validation_failed'))
      end

      private

      def normalized_attributes(params)
        normalized_identity_attributes(params).merge(normalized_reference_attributes(params))
      end

      def normalized_identity_attributes(params)
        {
          full_name: params[:full_name].to_s.strip,
          cnic: ::Candidates::CnicNormalizer.call(params[:cnic]),
          mobile_number: normalized_mobile_number(params[:mobile_number]),
          passport_number: normalized_passport_number(params[:passport_number]),
          preferred_locale: params[:preferred_locale].to_s.strip.downcase.presence || 'en'
        }.merge(normalized_next_of_kin_attributes(params))
      end

      def normalized_next_of_kin_attributes(params)
        {
          next_of_kin_name: params[:next_of_kin_name].to_s.strip.presence,
          next_of_kin_relationship: params[:next_of_kin_relationship].to_s.strip.presence,
          next_of_kin_mobile_number: normalized_mobile_number(params[:next_of_kin_mobile_number]).presence,
          next_of_kin_cnic: ::Candidates::CnicNormalizer.call(params[:next_of_kin_cnic]).presence
        }
      end

      def normalized_reference_attributes(params)
        {
          country_code: params[:country_code].to_s.strip.downcase,
          project_code: params[:project_code].to_s.strip.downcase,
          craft_code: params[:craft_code].to_s.strip.downcase,
          reference_number: params[:reference_number].to_s.strip.upcase
        }
      end

      def perform_creation
        candidate = create_candidate!
        assignment = create_assignment!(candidate)
        advance_workflow!(candidate:, assignment:)
        record_audit!(candidate)
        candidate.reload
      end

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_candidates')
      end

      def validate_payload!
        validate_full_name!
        validate_cnic!
        validate_mobile_number!
        validate_passport_number! if @params.passport_number.present?
        validate_next_of_kin!
        validate_preferred_locale!
        validate_reference_number!
        @country = validated_reference(Country, @params.country_code, field: 'country_code')
        @project = validated_reference(Project, @params.project_code, field: 'project_code')
        @craft = validated_reference(Craft, @params.craft_code, field: 'craft_code')
      end

      def validate_full_name!
        return if @params.full_name.present?

        raise_validation_error('full_name', 'api.errors.candidate_full_name_required')
      end

      def validate_cnic!
        raise_validation_error('cnic', 'api.errors.cnic_invalid') unless @params.cnic.match?(Candidate::CNIC_FORMAT)
        raise DuplicateCnicError if Candidate.exists?(cnic: @params.cnic)
      end

      def validate_mobile_number!
        return if @params.mobile_number.match?(Candidate::MOBILE_NUMBER_FORMAT)

        raise_validation_error('mobile_number', 'api.errors.candidate_mobile_number_invalid')
      end

      def validate_passport_number!
        unless @params.passport_number.match?(Candidate::PASSPORT_NUMBER_FORMAT)
          raise_validation_error('passport_number', 'api.errors.candidate_passport_number_invalid')
        end
        raise DuplicatePassportNumberError if Candidate.exists?(passport_number: @params.passport_number)
      end

      def validate_preferred_locale!
        return if Candidate::PREFERRED_LOCALES.include?(@params.preferred_locale)

        raise_validation_error('preferred_locale', 'api.errors.candidate_preferred_locale_invalid')
      end

      def validate_next_of_kin!
        fields = %i[next_of_kin_name next_of_kin_relationship next_of_kin_mobile_number next_of_kin_cnic]
        return if fields.all? { |field| @params.public_send(field).blank? }

        fields.each do |field|
          validate_next_of_kin_field!(field)
        end
        unless @params.next_of_kin_mobile_number.match?(Candidate::MOBILE_NUMBER_FORMAT)
          raise_validation_error('next_of_kin_mobile_number', 'api.errors.next_of_kin_mobile_number_invalid')
        end
        return if @params.next_of_kin_cnic.match?(Candidate::CNIC_FORMAT)

        raise_validation_error('next_of_kin_cnic', 'api.errors.next_of_kin_cnic_invalid')
      end

      def validate_next_of_kin_field!(field)
        return if @params.public_send(field).present?

        raise_validation_error(field.to_s, 'api.errors.next_of_kin_field_required')
      end

      def validate_reference_number!
        if @params.reference_number.blank?
          raise_validation_error('reference_number', 'api.errors.candidate_reference_number_required')
        end
        raise DuplicateReferenceNumberError if CandidateAssignment.exists?(reference_number: @params.reference_number)
      end

      def validated_reference(model, code, field:)
        record = model.active.find_by(code:)
        return record if record.present?

        raise_validation_error(field, "api.errors.unknown_#{field}")
      end

      def raise_validation_error(field, translation_key)
        raise ValidationError.new(field:, message: I18n.t(translation_key))
      end

      def create_candidate!
        Candidate.create!(candidate_attributes)
      end

      def candidate_attributes
        {
          full_name: @params.full_name, cnic: @params.cnic, mobile_number: @params.mobile_number,
          passport_number: @params.passport_number, preferred_locale: @params.preferred_locale,
          next_of_kin_name: @params.next_of_kin_name,
          next_of_kin_relationship: @params.next_of_kin_relationship,
          next_of_kin_mobile_number: @params.next_of_kin_mobile_number,
          next_of_kin_cnic: @params.next_of_kin_cnic,
          status_code: 'registered', active: true, source_code: 'admin_ui', created_by: @params.actor
        }
      end

      def create_assignment!(candidate)
        candidate.candidate_assignments.create!(
          reference_number: @params.reference_number,
          country: @country,
          project: @project,
          craft: @craft,
          current_workflow_stage: registered_stage,
          created_by: @params.actor
        )
      end

      def registered_stage
        @registered_stage ||= WorkflowStage.find_by!(code: 'registered')
      end

      def advance_workflow!(candidate:, assignment:)
        ::CandidateWorkflows::AutomaticTransitionService.call(
          candidate:,
          event: :assignment_created,
          actor: @params.actor,
          request_id: @params.request_id
        )
        assignment.reload
      end

      def record_audit!(candidate)
        ::Admin::Candidates::AuditRecorder.call(
          actor: @params.actor,
          candidate:,
          action_code: 'candidate_created',
          changed_fields: AUDITED_FIELDS
        )
      end

      def normalized_mobile_number(raw_value)
        value = raw_value.to_s.strip
        digits = value.gsub(/\D/, '')
        value.start_with?('+') ? "+#{digits}" : digits
      end

      def normalized_passport_number(raw_value)
        raw_value.to_s.upcase.gsub(/\s+/, '').presence
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
