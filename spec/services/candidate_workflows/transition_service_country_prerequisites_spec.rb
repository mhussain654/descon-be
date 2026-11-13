# frozen_string_literal: true

require 'rails_helper'

# Country-specific prerequisites and evidence (BE PR 3), plus the hold-and-re-decide
# behaviour of negative medical and visa outcomes.
RSpec.describe CandidateWorkflows::TransitionService do
  let(:actor) { create(:user, role: 'mps') }

  before { ensure_staff_authorization_reference_data! }

  def stage_for(code) = WorkflowStage.find_by!(code:)

  def candidate_at(code, country: process_country(:qatar))
    candidate = create(:candidate, status_code: code)
    assignment = create(:candidate_assignment, candidate:, country:, current_workflow_stage: stage_for(code))
    [candidate, assignment]
  end

  def transition!(candidate, to_stage_code, evidence = {})
    described_class.call(actor:, candidate:, to_stage_code:, evidence:, request_id: SecureRandom.uuid)
  end

  def blocking_reasons_for(candidate, to_stage_code, evidence = {})
    transition!(candidate, to_stage_code, evidence)
    []
  rescue WorkflowTransitionPrerequisiteError => e
    e.details.fetch(:blocking_reasons)
  end

  def pay!(assignment)
    create(:payment, candidate_assignment: assignment, status_code: 'paid', paid_at: Time.current,
                     external_reference: "PAY-#{SecureRandom.hex(4)}")
  end

  def record_medical!(candidate, outcome_code, expected:)
    CandidateWorkflows::MedicalResults::RecordService.call(
      actor:, candidate:, outcome_code:, result_date: '2026-08-22', expected_current_stage_code: expected,
      request_id: SecureRandom.uuid
    )
  end

  describe 'medical outcomes' do
    it 'records the result on entering the outcome stage and holds an unfit candidate until re-decided fit' do
      candidate, assignment = candidate_at('medical_appointment')

      result = record_medical!(candidate, 'unfit', expected: 'medical_appointment')

      expect(assignment.reload.current_workflow_stage.code).to eq('medical_fit')
      expect(result.fetch(:medical_result)).to have_attributes(outcome_code: 'unfit',
                                                               candidate_stage_history: be_present)
      expect(blocking_reasons_for(candidate, 'fee_pending')).to eq(['medical_fit_required'])

      re_decision = record_medical!(candidate, 'fit', expected: 'medical_fit')

      expect(re_decision.fetch(:medical_result)).to have_attributes(outcome_code: 'fit', candidate_stage_history: nil)
      expect(assignment.candidate_medical_results.count).to eq(2)
      expect(assignment.reload.current_workflow_stage.code).to eq('medical_fit')
      expect(re_decision.fetch(:snapshot).medical_result.outcome_code).to eq('fit')
      expect(AuditEvent.where(action_code: 'candidate_medical_result_recorded').count).to eq(2)
    end

    it 'refuses a medical result when the candidate is neither at nor next to a medical-outcome stage' do
      candidate, = candidate_at('verified')

      expect { record_medical!(candidate, 'fit', expected: 'verified') }.to raise_error(InvalidWorkflowTransitionError)
    end

    it 'requires a valid outcome and date for the result' do
      candidate, = candidate_at('gamca_medical_pending', country: process_country(:saudi_arabia))

      expect { transition!(candidate, 'gamca_medical_completed', medical_outcome_code: 'fit') }
        .to raise_error(WorkflowTransitionPrerequisiteError)
      expect do
        transition!(candidate, 'gamca_medical_completed', medical_outcome_code: 'healthy',
                                                          medical_result_date: '2026-08-22')
      end.to raise_error(ValidationError)
    end
  end

  describe 'visa decisions' do
    it 'requires the fee to be paid before any visa decision, in every process' do
      candidate, assignment = candidate_at('visa_processing', country: create(:country))
      visa = { visa_outcome_code: 'issued', visa_outcome_date: '2026-09-10' }

      expect(blocking_reasons_for(candidate, 'visa_issued_or_rejected', visa)).to eq(['payment_required'])

      pay!(assignment)
      transition!(candidate, 'visa_issued_or_rejected', visa)
      expect(assignment.reload.current_workflow_stage.code).to eq('visa_issued_or_rejected')
    end

    it 'holds a rejected candidate at the visa stage until an issued re-decision' do
      candidate, assignment = candidate_at('visa_stamping_case_sent', country: process_country(:saudi_arabia))
      pay!(assignment)
      transition!(candidate, 'visa_issued_or_rejected', visa_outcome_code: 'rejected', visa_outcome_date: '2026-09-10',
                                                        rejection_reason_code: 'embassy_rejection')
      protection_day = { appeared_for_protection_on: '2026-09-12' }

      expect(blocking_reasons_for(candidate, 'appeared_for_protection', protection_day)).to eq(['visa_issued_required'])

      create(:candidate_visa_decision, candidate_assignment: assignment, candidate_stage_history: nil,
                                       outcome_code: 'issued')
      transition!(candidate, 'appeared_for_protection', protection_day)
      expect(assignment.reload.current_workflow_stage.code).to eq('appeared_for_protection')
    end
  end

  it 'shares a Qatar candidate with the BU only when verified, paid and medically fit' do
    candidate, assignment = candidate_at('fee_paid')
    create(:document_requirement, country: assignment.country, required: true)
    create_verified_bank_detail(assignment:)
    Candidates::Documents::RequirementResolver.call(candidate:, assignment:).select(&:required).each do |requirement|
      assignment.candidate_documents.current_version
                .where(document_type: requirement.document_type)
                .find_each { |document| document.update!(superseded_at: Time.current) }
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: requirement.document_type,
        status_code: 'verified', verified_by: actor, verified_at: Time.current,
        issued_on: requirement.document_type.code == CandidateDocument::PCC_REQUIREMENT_CODE ? Date.current : nil
      )
    end
    pay!(assignment)
    create(:candidate_medical_result, candidate_assignment: assignment, outcome_code: 'unfit')

    expect(blocking_reasons_for(candidate, 'documents_shared_with_qatar_bu')).to eq(['medical_fit_required'])
  end

  it 'requires the fee before a KSA visa stamping case is sent' do
    candidate, = candidate_at('visa_stamping_case_prepared', country: process_country(:saudi_arabia))

    expect(blocking_reasons_for(candidate, 'visa_stamping_case_sent')).to eq(['payment_required'])
  end

  it 'requires E-number, biometric, protection call and ticket handover evidence' do
    {
      ['e_number_requested', :saudi_arabia] => %w[e_number_received e_number_required],
      ['e_number_received', :saudi_arabia] => %w[biometric_completed biometric_completed_on_required],
      ['visa_issued_or_rejected', :qatar] => %w[protection_call protection_call_status_required],
      ['appeared_for_protection', :saudi_arabia] => %w[ticket_handover ticket_handed_over_on_required]
    }.each do |(from, country), (to, reason)|
      candidate, assignment = candidate_at(from, country: process_country(country))
      create(:candidate_visa_decision, candidate_assignment: assignment, candidate_stage_history: nil,
                                       outcome_code: 'issued')

      expect(blocking_reasons_for(candidate, to)).to eq([reason])
    end
  end

  it 'offers the next transition with its form fields and the hold reason' do
    candidate, assignment = candidate_at('medical_fit')
    create(:candidate_medical_result, candidate_assignment: assignment, outcome_code: 'unfit')

    next_transition = CandidateWorkflows::AllowedTransitionsService.call(actor:, candidate:).sole

    expect(next_transition).to include(code: 'fee_pending', allowed: false, blocking_reasons: ['medical_fit_required'])

    candidate, = candidate_at('e_number_requested', country: process_country(:saudi_arabia))
    expect(CandidateWorkflows::AllowedTransitionsService.call(actor:, candidate:).sole.fetch(:fields)).to eq(
      [{ name: 'e_number', type: 'string', required: true },
       { name: 'e_number_received_on', type: 'iso_date', required: true }]
    )
  end

  describe 'the medical appointment details' do
    before { MedicalAppointmentSetting.delete_all }

    def medical_appointment_fields(candidate)
      CandidateWorkflows::AllowedTransitionsService.call(actor:, candidate:).sole.fetch(:fields)
    end

    it 'offers the centre, address, date and time, filled in with the admin defaults that are set' do
      MedicalAppointmentSetting.current.update!(center_name: 'Al Shifa Medical Centre', appointment_on: '2026-11-20',
                                                appointment_time: '09:30')
      candidate, = candidate_at('campaign_nomination')

      expect(medical_appointment_fields(candidate)).to eq(
        [{ name: 'medical_center_name', type: 'string', required: false, default: 'Al Shifa Medical Centre' },
         { name: 'medical_center_address', type: 'string', required: false },
         { name: 'medical_appointment_date', type: 'iso_date', required: false, default: '2026-11-20' },
         { name: 'medical_appointment_time', type: 'time', required: false, default: '09:30' }]
      )
    end

    it "saves the details sent with the move on the candidate's history, untouched by later default changes" do
      MedicalAppointmentSetting.current.update!(center_name: 'Old Centre', appointment_time: '09:30')
      candidate, assignment = candidate_at('campaign_nomination')
      details = { 'medical_center_name' => 'Al Shifa Medical Centre',
                  'medical_center_address' => '12 Mall Road, Lahore',
                  'medical_appointment_date' => '2026-11-20', 'medical_appointment_time' => '10:15' }

      transition!(candidate, 'medical_appointment', details)
      MedicalAppointmentSetting.current.update!(center_name: 'New Centre', appointment_time: '14:00')

      expect(assignment.candidate_stage_histories.order(:id).last.metadata).to eq(details)
    end

    it 'refuses a time that is not HH:MM on a 24-hour clock' do
      candidate, = candidate_at('campaign_nomination')

      expect { transition!(candidate, 'medical_appointment', { 'medical_appointment_time' => '9:30 am' }) }
        .to raise_error(ValidationError) do |error|
          expect(error.field).to eq('candidate_workflow_transition.evidence.medical_appointment_time')
        end
    end
  end
end
