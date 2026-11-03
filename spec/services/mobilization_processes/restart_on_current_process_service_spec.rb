# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MobilizationProcesses::RestartOnCurrentProcessService do
  def retired_process(code)
    MobilizationProcess.find_by!(code:, version: 1, status: 'retired')
  end

  def stage(code) = WorkflowStage.find_by!(code:)

  # As if created before the finalized flows were published.
  def assignment_on(process, country:, stage_code:)
    create(:candidate_assignment, candidate: create(:candidate, status_code: stage_code), country:,
                                  mobilization_process: process, current_workflow_stage: stage(stage_code))
  end

  context 'when candidates are still on a retired process' do
    it 'restarts each at the first stage of their country flow and audits the move' do
      ksa = assignment_on(retired_process('ksa_mobilization'), country: process_country(:saudi_arabia),
                                                               stage_code: 'visa_stamping_case_prepared')
      uae = assignment_on(retired_process('common_mobilization'), country: process_country(:uae),
                                                                  stage_code: 'fee_pending')

      expect(described_class.call).to contain_exactly(ksa, uae)

      expect(ksa.reload.mobilization_process).to have_attributes(code: 'ksa_mobilization', version: 2)
      expect(uae.reload.mobilization_process).to have_attributes(code: 'uae_mobilization', version: 1)
      [ksa, uae].each do |assignment|
        expect(assignment.current_workflow_stage.code).to eq('registered')
        expect(assignment.current_mobilization_process_stage).to eq(assignment.mobilization_process.first_stage)
        expect(assignment.candidate.reload.status_code).to eq('registered')
      end
      expect(AuditEvent.find_by!(action_code: described_class::ACTION_CODE, entity_id: ksa.id).metadata)
        .to include('from_process' => 'ksa_mobilization v1', 'to_process' => 'ksa_mobilization v2')
    end
  end

  context 'when a candidate is on the common process but their country has its own flow' do
    it 'moves them onto their country flow' do
      common = MobilizationProcess.active.find_by!(country_id: nil)
      qatar = assignment_on(common, country: process_country(:qatar), stage_code: 'documents_pending')
      kuwait = assignment_on(common, country: create(:country, code: 'kuwait'), stage_code: 'documents_pending')

      expect(described_class.call).to contain_exactly(qatar)

      expect(qatar.reload.mobilization_process).to have_attributes(code: 'qatar_mobilization', version: 1)
      expect(qatar.current_workflow_stage.code).to eq('registered')
      expect(kuwait.reload.mobilization_process).to eq(common)
    end
  end

  context 'when every candidate is already on their country flow' do
    it 'changes nothing, so running it again is safe' do
      assignment = create(:candidate_assignment, country: process_country(:qatar),
                                                 current_workflow_stage: stage('verified'))

      expect(described_class.call).to be_empty
      expect(assignment.reload.current_workflow_stage.code).to eq('verified')
      expect(AuditEvent.where(action_code: described_class::ACTION_CODE)).to be_empty
    end
  end
end
