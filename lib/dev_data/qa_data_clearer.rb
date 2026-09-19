# frozen_string_literal: true

module DevData
  # Removes everything QaDataSeeder created, in FK-safe order (children before parents --
  # this app uses real `dependent: :restrict_with_exception` associations throughout, so a
  # parent can't be deleted while a child row still references it). Development-only, invoked
  # via `bin/rails dev_data:clear_qa_data`.
  class QaDataClearer
    def self.call = new.call

    def call
      raise 'dev_data:clear_qa_data only runs in the development environment.' unless Rails.env.development?

      candidate_ids = Candidate.where('full_name LIKE ?', "#{QaDataSeeder::SEED_TAG}%").pluck(:id)
      return 0 if candidate_ids.empty?

      assignment_ids = CandidateAssignment.where(candidate_id: candidate_ids).pluck(:id)

      ActiveRecord::Base.transaction do
        clear_candidate_graph!(candidate_ids, assignment_ids)
        clear_unrelated_seed_data!
      end

      candidate_ids.size
    end

    private

    # Deepest children first: every table hanging off a QA candidate/assignment via
    # `dependent: :restrict_with_exception`, in dependency order.
    def clear_candidate_graph!(candidate_ids, assignment_ids)
      clear_assignment_children!(assignment_ids)
      CandidateAssignment.where(id: assignment_ids).delete_all
      CandidateConsent.where(candidate_id: candidate_ids).delete_all
      Candidate.where(id: candidate_ids).delete_all
    end

    # A long, strictly-ordered sequence of one-line deletes is the actual point here -- splitting
    # it further would hide the FK order this method exists to get right, not clarify it.
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def clear_assignment_children!(assignment_ids)
      clear_ai_calls(assignment_ids)
      clear_communications(assignment_ids)
      clear_document_submissions(assignment_ids)
      CandidateDocument.where(candidate_assignment_id: assignment_ids).find_each(&:destroy!)
      clear_payment_reconciliation(assignment_ids)
      PaymentEvent.where(candidate_assignment_id: assignment_ids).delete_all
      Payment.where(candidate_assignment_id: assignment_ids).delete_all
      CandidateVisaDecision.where(candidate_assignment_id: assignment_ids).delete_all
      CandidateProtectionRecord.where(candidate_assignment_id: assignment_ids).delete_all
      CandidateFlightDetail.where(candidate_assignment_id: assignment_ids).delete_all
      CandidateQvcAttempt.where(candidate_assignment_id: assignment_ids).delete_all
      CandidateStageHistory.where(candidate_assignment_id: assignment_ids).delete_all
      AuditEvent.where(candidate_assignment_id: assignment_ids).delete_all
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # Data seeded independently of any candidate (imports, backups, script activations, users).
    def clear_unrelated_seed_data!
      clear_candidate_imports
      clear_database_backups
      clear_workflow_stage_script_activations
      clear_users
    end

    def clear_ai_calls(assignment_ids)
      call_ids = CandidateAiCall.where(candidate_assignment_id: assignment_ids).pluck(:id)
      CandidateAiCallEvent.where(candidate_ai_call_id: call_ids).delete_all
      CandidateAiCallTranscript.where(candidate_ai_call_id: call_ids).delete_all
      CandidateAiCall.where(id: call_ids).delete_all
    end

    def clear_communications(assignment_ids)
      Communication.where(candidate_assignment_id: assignment_ids).delete_all
    end

    def clear_document_submissions(assignment_ids)
      submission_ids = CandidateDocumentSubmission.where(candidate_assignment_id: assignment_ids).pluck(:id)
      CandidateDocumentSubmissionItem.where(candidate_document_submission_id: submission_ids).delete_all
      CandidateDocumentSubmission.where(id: submission_ids).delete_all
    end

    def clear_payment_reconciliation(assignment_ids)
      payment_ids = Payment.where(candidate_assignment_id: assignment_ids).pluck(:id)
      run_ids = PaymentReconciliationFinding.where(payment_id: payment_ids).pluck(:payment_reconciliation_run_id).uniq
      PaymentReconciliationFinding.where(payment_id: payment_ids).delete_all
      PaymentReconciliationRun.where(id: run_ids).delete_all
    end

    def clear_candidate_imports
      batch_ids = CandidateImportBatch.where(actor_id: qa_user_ids).pluck(:id)
      CandidateImportRowResult.where(candidate_import_batch_id: batch_ids).delete_all
      CandidateImportBatch.where(id: batch_ids).delete_all
    end

    def clear_database_backups
      SystemDatabaseBackup.where('checksum_sha256 LIKE ?', 'qaseed%').find_each(&:destroy!)
    end

    def clear_workflow_stage_script_activations
      WorkflowStageCallScript.where(workflow_stage_code: %w[verified fee_paid mobilized]).update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
    end

    def clear_users
      User.where(id: qa_user_ids).delete_all
    end

    def qa_user_ids
      @qa_user_ids ||= User.where('email LIKE ?', 'qa-%@descon.local').pluck(:id)
    end
  end
end
