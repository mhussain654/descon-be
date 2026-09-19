# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Dashboards::AdminSummaryService do
  def stage(code, position)
    WorkflowStage.find_or_create_by!(code:) do |record|
      record.position = position
      record.system_defined = true
    end
  end

  def build_pending_review_submission(assignment)
    submission = create(:candidate_document_submission, candidate_assignment: assignment)
    document = create(:candidate_document, candidate_assignment: assignment, status_code: 'under_verification')
    create(:candidate_document_submission_item, candidate_document_submission: submission, candidate_document: document,
                                                requirement_code: 'req_1', required: true)
  end

  it 'assembles candidate workload, workflow-stage queue, document-review queue and payment sections' do
    registered_stage = stage('registered', 1)
    create(:candidate_assignment, current_workflow_stage: registered_stage, candidate: create(:candidate, active: true))
    create(:candidate_document_submission)
    create(:payment)

    result = described_class.call

    expect(result.fetch(:candidate_workload)).to eq(total_active_candidates: Candidate.active.count)
    expect(result.fetch(:workflow_stage_queue)).to be_an(Array)
    expect(result.fetch(:document_review_queue).keys).to contain_exactly(
      'pending_review', 'verified', 'rejected', 'expired_pcc', 'near_expiry_pcc'
    )
    expect(result.fetch(:payment_summary)).to be_an(Array)
  end

  it 'includes the conversion funnel and average stage duration' do
    result = described_class.call

    expect(result.fetch(:conversion_funnel)).to be_an(Array)
    expect(result.fetch(:conversion_funnel).pluck(:code)).to contain_exactly('documents_uploaded', 'verified',
                                                                             'mobilized')
    expect(result.fetch(:average_stage_duration_days)).to be_nil.or be_a(Numeric)
  end

  it 'assembles requires_attention from existing sections plus overdue QVC and callback-required calls' do
    verified_stage = stage('verified', 5)
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage)
    create(:payment, candidate_assignment: assignment, status_code: 'failed')
    create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: 2.days.ago)
    create(:candidate_ai_call, candidate: assignment.candidate, candidate_assignment: assignment,
                               outcome: 'callback_required', completed_at: 1.day.ago)

    result = described_class.call
    attention = result.fetch(:requires_attention).index_by { |row| row.fetch(:code) }

    # Consistency, not DocumentReviewQueueQuery's own business logic (that
    # has its own dedicated spec) -- requires_attention must read the exact
    # same number document_review_queue itself reports, never a second,
    # independently-computed rejected-count that could drift from it.
    expect(attention.dig('rejected_documents', :count)).to eq(result.fetch(:document_review_queue).fetch('rejected'))
    expect(attention.dig('failed_payment', :count)).to eq(1)
    expect(attention.dig('overdue_qvc', :count)).to eq(1)
    expect(attention.dig('callback_required', :count)).to eq(1)
  end

  it 'includes upcoming activities, recently-updated candidates and KPI trends' do
    stage('registered', 1)
    verified_stage = stage('verified', 5)
    assignment = create(:candidate_assignment, current_workflow_stage: verified_stage)
    create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: 2.days.from_now)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: verified_stage)

    result = described_class.call

    expect(result.fetch(:upcoming_activities)).to be_an(Array)
    expect(result.fetch(:upcoming_activities).first).to include(:type, :occurs_on, :candidate_assignment_public_id)
    expect(result.fetch(:recently_updated_candidates)).to be_an(Array)
    expect(result.fetch(:recently_updated_candidates).first).to include(:candidate_full_name, :workflow_stage_code)
    expect(result.fetch(:kpi_trends).keys).to contain_exactly(:active_candidates, :paid_payments, :mobilized)
  end

  it 'scopes every section (including document_review_queue) to the requested country/project/craft filters' do
    country = create(:country)
    project = create(:project)
    craft = create(:craft)
    matching_assignment = create(:candidate_assignment, country:, project:, craft:)
    build_pending_review_submission(matching_assignment)
    other_assignment = create(:candidate_assignment)
    build_pending_review_submission(other_assignment)

    result = described_class.call(
      params: ActionController::Parameters.new(
        filter: { country_code: country.code, project_code: project.code, craft_code: craft.code }
      )
    )

    expect(result.fetch(:candidate_workload)).to eq(total_active_candidates: 1)
    expect(result.fetch(:document_review_queue).fetch('pending_review')).to eq(1)
  end

  it 'propagates an unknown filter code as InvalidQueryParameterError' do
    expect do
      described_class.call(params: ActionController::Parameters.new(filter: { country_code: 'not_a_real_country' }))
    end.to raise_error(InvalidQueryParameterError)
  end
end
