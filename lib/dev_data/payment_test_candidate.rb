# frozen_string_literal: true

module DevData
  # Picks a QA candidate who is at the fee stage and can pay, and gives them a known one-hour
  # login code, so the payment screen can be tried locally without an SMS. Development only;
  # invoked via `bin/rails dev_data:payment_test_candidate` (lib/tasks/dev_data.rake).
  class PaymentTestCandidate
    CODE = '123456'

    # With a CNIC, that candidate is used (they must be at the fee stage); without, any candidate who can pay.
    def self.call(cnic: nil)
      raise 'dev_data:payment_test_candidate only runs in the development environment.' unless Rails.env.development?

      candidate = cnic.present? ? new.candidate_by_cnic(cnic) : new.find_candidate
      raise 'No candidate at the fee stage can pay. Run dev_data:seed_qa_data first.' if candidate.blank?

      give_login_code(candidate)
      candidate
    end

    def self.give_login_code(candidate)
      CandidateOtpChallenge.where(cnic: candidate.cnic).delete_all
      CandidateOtpChallenge.create!(candidate:, cnic: candidate.cnic, code_digest: BCrypt::Password.create(CODE),
                                    expires_at: 1.hour.from_now)
    end

    # A fee-stage candidate whose fee is not already paid or waiting on a payment.
    def find_candidate
      fee_pending = WorkflowStage.find_by!(code: 'fee_pending')
      Candidate.active.joins(:candidate_assignments)
               .where(candidate_assignments: { current_workflow_stage_id: fee_pending.id })
               .find { |candidate| payable?(candidate) }
    end

    def candidate_by_cnic(cnic)
      candidate = Candidate.active.find_by(cnic: Candidates::CnicNormalizer.call(cnic))
      raise 'No active candidate has that CNIC.' if candidate.blank?
      unless Payments::EligibilityService.call(candidate:).eligible
        raise 'That candidate is not at the fee stage and able to pay.'
      end

      candidate
    end

    private

    def payable?(candidate)
      Payments::EligibilityService.call(candidate:).eligible &&
        candidate.current_assignment.payments.none? { |payment| payment.paid? || open?(payment) }
    end

    def open?(payment)
      payment.checkout_pending? && payment.checkout_expires_at&.future?
    end
  end
end
