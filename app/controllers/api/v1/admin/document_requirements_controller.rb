# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Developer-only document checklist editor: every checklist row (common
      # and per country, on or off), adding a document to a checklist, and
      # editing a row's candidate-facing settings.
      class DocumentRequirementsController < ProtectedStaffController
        EDITABLE_PARAMS = [:requirement_level, :active, :maximum_files, :instructions_en, :instructions_ur,
                           { accepted_content_types: [] }].freeze

        def index
          authorize :reference_data, :manage?, policy_class: ::Admin::ReferenceDataPolicy

          render_success(data: checklist)
        end

        def create
          authorize :reference_data, :manage?, policy_class: ::Admin::ReferenceDataPolicy

          attributes = params.expect(document_requirement: [:document_type_code, :country_code, *EDITABLE_PARAMS])
          render_idempotent_response(scope: 'admin.document_requirements.create', subject: current_user,
                                     fingerprint: attributes.to_h.to_json, required: true) do
            success_payload(data: serialized(mutate(attributes:)), status: :created)
          end
        end

        def update
          authorize :reference_data, :manage?, policy_class: ::Admin::ReferenceDataPolicy

          attributes = params.fetch(:document_requirement, {}).permit(:expected_updated_at, *EDITABLE_PARAMS)
          updated = mutate(
            requirement: DocumentRequirement.find(params.expect(:id)),
            attributes: attributes.except(:expected_updated_at),
            expected_updated_at: attributes[:expected_updated_at]
          )
          render_success(data: serialized(updated))
        end

        private

        def checklist
          {
            requirements: requirements.map { |requirement| serialized(requirement) },
            document_types: DocumentType.where(active: true).order(:code)
                                        .map { |type| ::Admin::DocumentRequirementSerializer.ref(type) },
            content_types: DocumentRequirement::CONTENT_TYPES
          }
        end

        def mutate(**)
          ::Admin::DocumentRequirements::MutationService.call(actor: current_user, request_id: request.request_id, **)
        end

        def requirements
          policy_scope(DocumentRequirement, policy_scope_class: ::Admin::ReferenceDataPolicy::ManagedScope)
            .includes(:document_type, :country, :project, :craft)
            .order(Arel.sql('country_id IS NOT NULL'), :country_id, :display_position, :id)
        end

        def serialized(requirement) = ::Admin::DocumentRequirementSerializer.new(requirement).as_json
      end
    end
  end
end
