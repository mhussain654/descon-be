# frozen_string_literal: true

require 'factory_bot'
require Rails.root.join('lib/dev_data/candidate_fixture_builder')

module DevData
  # Generates a broad dataset -- candidates spread across every workflow stage (via
  # CandidateFixtureBuilder), plus communications, audit events, document submissions, payment
  # reconciliation, an import batch, and database backups -- so every admin tab and filter
  # combination has real data to click through manually. Invoked only via
  # `bin/rails dev_data:seed_qa_data` (lib/tasks/dev_data.rake).
  #
  # Deliberately lives under lib/, not app/services/: this never runs as part of the application
  # itself (only a developer manually running the rake task), so it isn't held to the app's normal
  # spec-coverage requirement the way a real request-path or rake-invoked operational service
  # (e.g. Backups::RestoreDatabaseBackupService) is.
  # rubocop:disable Metrics/ClassLength
  class QaDataSeeder
    include FactoryBot::Syntax::Methods

    PASSWORD = 'Testing@123'
    COMMUNICATION_CHANNELS = %w[sms whatsapp email].freeze
    COMMUNICATION_STATUSES = %w[sent delivered failed].freeze
    AUDIT_ACTIONS = %w[created updated workflow_transitioned].freeze

    Profile = Struct.new(
      :stage, :documents, :qvc, :visa, :protection, :flight, :payment, :ai_call, :verification,
      :consent_accepted,
      keyword_init: true
    )

    PROFILES = [
      # `registered` is deliberately never used as a target stage here: every
      # real candidate is created together with its first assignment
      # (Admin::Candidates::CreateService / Imports::RowPersister), and both
      # call CandidateWorkflows::AutomaticTransitionService right after with
      # event: :assignment_created -- which immediately advances a real
      # candidate to `documents_pending`. A candidate whose *current* stage
      # is `registered` is therefore not a state any real candidate is ever
      # observed in; seeding one here would show a demo candidate stuck in a
      # workflow/UI state production never produces.
      Profile.new(stage: 'documents_pending', documents: :none,
                  ai_call: { direction: 'inbound', verification: 'failed' }),
      Profile.new(stage: 'documents_pending', documents: :none),
      # Consent is a gate orthogonal to workflow stage (Api::V1::Candidate::ProtectedController
      # blocks every candidate endpoint except /consents until the current policy version is
      # accepted) -- a candidate who hasn't accepted it yet is otherwise a completely ordinary
      # freshly-created candidate, so this profile is identical to the plain documents_pending
      # one above except for consent_accepted: false.
      Profile.new(stage: 'documents_pending', documents: :none, consent_accepted: false),
      Profile.new(stage: 'documents_pending', documents: :partial),
      Profile.new(stage: 'documents_uploaded', documents: :all_uploaded),
      Profile.new(stage: 'documents_uploaded', documents: :one_rejected,
                  ai_call: { direction: 'outbound', call_reason: 'missing_documents', outcome: 'answered',
                             outcome_reason: 'unresolved' }),
      Profile.new(stage: 'under_verification', documents: :all_pending_review),
      Profile.new(stage: 'under_verification', documents: :mixed_pending_and_rejected),
      Profile.new(stage: 'verified', documents: :expired_pcc),
      Profile.new(stage: 'verified', documents: :all_verified,
                  ai_call: { direction: 'outbound', call_reason: 'workflow_stage_notification', outcome: 'answered',
                             outcome_reason: 'resolved' }),
      Profile.new(stage: 'fee_pending', documents: :all_verified, payment: :checkout_pending),
      Profile.new(stage: 'fee_pending', documents: :all_verified, payment: :failed),
      Profile.new(stage: 'fee_pending', documents: :all_verified, payment: :cancelled),
      Profile.new(stage: 'fee_paid', documents: :all_verified, payment: :paid,
                  ai_call: { direction: 'outbound', call_reason: 'workflow_stage_notification', outcome: 'answered',
                             outcome_reason: 'resolved' }),
      Profile.new(stage: 'documents_shared_with_qatar_bu', documents: :all_verified, payment: :paid),
      Profile.new(stage: 'qvc_appointment_booked', documents: :all_verified, payment: :paid, qvc: :scheduled),
      Profile.new(stage: 'qvc_appointment_booked', documents: :all_verified, payment: :paid, qvc: :re_medical),
      Profile.new(stage: 'qvc_completed_outcome_received', documents: :all_verified, payment: :paid, qvc: :approved),
      Profile.new(stage: 'qvc_completed_outcome_received', documents: :all_verified, payment: :paid, qvc: :rejected,
                  ai_call: { direction: 'outbound', call_reason: 'urgent_compliance_action',
                             outcome: 'callback_required', outcome_reason: 'agent_escalation' }),
      Profile.new(stage: 'qvc_completed_outcome_received', documents: :all_verified, payment: :paid, qvc: :no_show),
      # Every profile from here on reaches a stage a real candidate can only reach after
      # documents were verified and the fee was paid (both are workflow prerequisites of
      # these later stages) -- `documents: :all_verified, payment: :paid` is carried
      # forward on all of them so their checklist/payment data matches that reality,
      # instead of showing 0 documents and no payment for a candidate this far along.
      Profile.new(stage: 'visa_issued_or_rejected', documents: :all_verified, payment: :paid,
                  qvc: :approved, visa: :issued,
                  ai_call: { direction: 'inbound', verification: 'verified', outcome: 'answered',
                             outcome_reason: 'resolved', call_reason: 'general_helpline' }),
      Profile.new(stage: 'visa_issued_or_rejected', documents: :all_verified, payment: :paid,
                  qvc: :approved, visa: :rejected,
                  ai_call: { direction: 'outbound', call_reason: 'urgent_compliance_action',
                             needs_manual_review: true }),
      Profile.new(stage: 'appeared_for_protection', documents: :all_verified, payment: :paid,
                  visa: :issued, protection: :appeared_only,
                  ai_call: { direction: 'outbound', call_reason: 'protection_appearance_reminder',
                             outcome: 'answered', outcome_reason: 'resolved' }),
      Profile.new(stage: 'ticket_handover', documents: :all_verified, payment: :paid,
                  visa: :issued, protection: :appeared_only),
      Profile.new(stage: 'flight_details_uploaded', documents: :all_verified, payment: :paid,
                  protection: :appeared_only, flight: :scheduled,
                  ai_call: { direction: 'outbound', call_reason: 'flight_information', outcome: 'answered',
                             outcome_reason: 'resolved' }),
      Profile.new(stage: 'mobilized', documents: :all_verified, payment: :paid,
                  protection: :appeared_only, flight: :mobilized,
                  ai_call: { direction: 'outbound', call_reason: 'workflow_stage_notification',
                             needs_manual_review: true, resolve: true })
    ].freeze

    def self.call = new.call

    def call
      guard!

      @users_by_role = seed_users
      @reference = load_reference_data
      builder = CandidateFixtureBuilder.new

      candidates = PROFILES.each_with_index.map do |profile, index|
        builder.build(profile:, index:, actor: actor_for(index), reference: @reference)
      end

      seed_cross_cutting_data(candidates)
      candidates
    end

    private

    def guard!
      raise 'dev_data:seed_qa_data only runs in the development environment.' unless Rails.env.development?
      return unless Candidate.exists?(created_by_id: qa_user_ids)

      raise 'QA seed data already present (candidates created by a qa-*@descon.local user exist). ' \
            'Clear it first with `bin/rails dev_data:clear_qa_data` before reseeding.'
    end

    # Any qa-*@descon.local user already in the database, from a previous seed run -- used only
    # to detect leftover QA data before this run creates its own (see seed_users_for_role, which
    # re-creates the same accounts fresh either way).
    def qa_user_ids
      User.where('email LIKE ?', 'qa-%@descon.local').pluck(:id)
    end

    def seed_cross_cutting_data(candidates)
      seed_extra_communications(candidates)
      seed_audit_events(candidates)
      seed_document_submissions(candidates)
      seed_payment_reconciliation(candidates)
      seed_candidate_import
      seed_database_backups
      enable_some_workflow_stage_scripts
    end

    # ------------------------------------------------------------------------
    # Reference data / users
    # ------------------------------------------------------------------------

    def seed_users
      %w[admin hr mps finance management].index_with { |role| seed_users_for_role(role) }
    end

    def seed_users_for_role(role)
      Array.new(2) do |n|
        User.find_or_create_by!(email: "qa-#{role}#{n + 1}@descon.local") do |user|
          user.password = PASSWORD
          user.role = role
          user.staff_state = 'active'
        end
      end
    end

    def load_reference_data
      { countries: Country.active.to_a, projects: Project.active.to_a, crafts: Craft.active.to_a }
    end

    def actor_for(index) = @users_by_role.fetch(%w[hr mps finance management].fetch(index % 4)).first

    # ------------------------------------------------------------------------
    # Cross-cutting: communications, audit events, imports, backups, scripts
    # ------------------------------------------------------------------------

    def seed_extra_communications(candidates)
      candidates.first(6).each_with_index { |entry, i| build_communication(entry, i) }
    end

    def build_communication(entry, index)
      create(:communication, candidate_assignment: entry.fetch(:assignment), initiated_by: actor_for(index),
                             channel_code: COMMUNICATION_CHANNELS.fetch(index % 3), direction_code: 'outbound',
                             status_code: COMMUNICATION_STATUSES.fetch(index % 3),
                             template_code: 'application_status_update')
    end

    def seed_audit_events(candidates)
      candidates.first(10).each_with_index { |entry, i| build_audit_event(entry, i) }
    end

    def build_audit_event(entry, index)
      create(:audit_event, candidate_assignment: entry.fetch(:assignment), candidate: entry.fetch(:candidate),
                           actor: actor_for(index), entity_type: 'CandidateAssignment',
                           entity_id: entry.fetch(:assignment).id, action_code: AUDIT_ACTIONS.fetch(index % 3),
                           occurred_at: (10 - index).days.ago)
    end

    # Attaches a CandidateDocumentSubmission to every candidate that already has real
    # CandidateDocument rows, so the admin document-submissions review queue isn't empty.
    def seed_document_submissions(candidates)
      candidates.each_with_index { |entry, i| build_document_submission(entry, i) }
    end

    def build_document_submission(entry, index)
      assignment = entry.fetch(:assignment)
      documents = assignment.candidate_documents.to_a
      return if documents.empty?

      submission = create(:candidate_document_submission, candidate_assignment: assignment, status_code: 'submitted',
                                                          submitted_at: (documents.size + index).hours.ago)
      documents.each { |candidate_document| build_submission_item(submission, candidate_document) }
    end

    def build_submission_item(submission, candidate_document)
      create(:candidate_document_submission_item, candidate_document_submission: submission, candidate_document:,
                                                  requirement_code: candidate_document.document_type.code)
    end

    def seed_payment_reconciliation(candidates)
      paid_payments = candidates.filter_map { |entry| entry.fetch(:assignment).payments.find_by(status_code: 'paid') }
      return if paid_payments.empty?

      run = create(:payment_reconciliation_run, initiated_by: @users_by_role.fetch('finance').first,
                                                status_code: 'completed', run_date: 1.day.ago.to_date)
      create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment: paid_payments.first,
                                              finding_code: 'external_reference_missing', state_code: 'open')
    end

    # row_number > 1 -- row 1 is the CSV header, so real data rows start at 2.
    def seed_candidate_import
      batch = create(:candidate_import_batch, actor: @users_by_role.fetch('hr').first, status: 'completed')
      create(:candidate_import_row_result, candidate_import_batch: batch, row_number: 2, status: 'accepted')
      create(:candidate_import_row_result, candidate_import_batch: batch, row_number: 3, status: 'rejected',
                                           error_field: 'cnic', error_code: 'duplicate_candidate')
    end

    # `checksum_sha256` is tagged with a recognizable prefix (a real backup's checksum would
    # never happen to start with this) so QaDataClearer can find these rows precisely, rather
    # than guessing by a heuristic like "recently created".
    def seed_database_backups
      checksum = "qaseed#{SecureRandom.hex(29)}"
      create(:system_database_backup, :with_archive, status_code: 'succeeded', taken_at: 1.day.ago,
                                                     checksum_sha256: checksum)
      create(:system_database_backup, status_code: 'failed', taken_at: 2.days.ago, checksum_sha256: checksum)
    end

    def enable_some_workflow_stage_scripts
      WorkflowStageCallScript.where(workflow_stage_code: %w[verified fee_paid mobilized])
                             .update_all(active: true) # rubocop:disable Rails/SkipsModelValidations
    end
  end
  # rubocop:enable Metrics/ClassLength
end
