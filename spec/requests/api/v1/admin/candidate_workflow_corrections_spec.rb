# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Workflow Corrections', type: :request do
  let(:developer) { create(:user, role: 'developer') }
  let(:candidate) { create(:candidate, status_code: stage_code) }
  let(:assignment) do
    create(:candidate_assignment, candidate:, country: process_country(:qatar),
                                  current_workflow_stage: stage(stage_code))
  end
  let(:stage_code) { 'medical_appointment' }

  before { ensure_staff_authorization_reference_data! }

  def stage(code) = WorkflowStage.find_by!(code:)

  def base_path = "/api/v1/admin/candidates/#{candidate.public_id}/workflow_corrections"

  def auth_headers(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def correct(kind, values, user: developer)
    patch "#{base_path}/#{kind}", params: { workflow_correction: values }, headers: auth_headers(user)
  end

  def medical_entry!
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: stage('medical_appointment'),
                                     metadata: { 'medical_center_name' => 'Old Centre',
                                                 'medical_appointment_date' => '2026-11-20' })
  end

  def candidate_history_details
    CandidateWorkflows::StateSnapshotService.call(candidate:).history.last[:details]
  end

  describe 'who may use it' do
    it 'is for developers only: admin, MPS and HR are refused' do
      medical_entry!

      %w[admin mps hr].each do |role|
        get base_path, headers: auth_headers(create(:user, role:))
        expect(response).to have_http_status(:forbidden)

        correct(:medical_appointment, { reason: 'x', center_name: 'New' }, user: create(:user, role:))
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET' do
    it 'shows each box with its values and whether it can be changed' do
      medical_entry!

      get base_path, headers: auth_headers(developer)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      expect(data.fetch('medical_appointment')).to include(
        'editable' => true, 'blocked_reason' => nil,
        'values' => include('center_name' => 'Old Centre', 'appointment_date' => '2026-11-20')
      )
      expect(data.fetch('qvc_appointment')).to include('editable' => false, 'blocked_reason' => 'not_recorded')
      expect(data.fetch('flight_detail')).to include('editable' => false, 'blocked_reason' => 'not_recorded')
    end
  end

  describe 'PATCH medical_appointment' do
    it 'corrects the appointment without moving the candidate, keeps the original, audits it and texts the candidate' do
      entry = medical_entry!

      correct(:medical_appointment, { reason: 'Candidate cannot reach this centre', center_name: 'Al Shifa',
                                      center_address: 'Mall Road, Lahore', appointment_date: '2026-11-25',
                                      appointment_time: '10:00' })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'medical_appointment', 'values')).to include(
        'center_name' => 'Al Shifa', 'appointment_date' => '2026-11-25', 'appointment_time' => '10:00'
      )
      expect(candidate_history_details).to include('medical_center_name' => 'Al Shifa',
                                                   'medical_appointment_date' => '2026-11-25')
      expect(entry.reload.metadata).to include('medical_center_name' => 'Old Centre')
      expect(assignment.reload.current_workflow_stage.code).to eq('medical_appointment')

      audit = AuditEvent.find_by!(action_code: 'medical_appointment_corrected')
      expect(audit).to have_attributes(actor: developer, note: 'Candidate cannot reach this centre')
      expect(audit.metadata.dig('changes', 'medical_center_name')).to eq(['Old Centre', 'Al Shifa'])
      expect(CandidateSmsDelivery.find_by!(message_code: 'medical_appointment_changed').variables)
        .to include('date' => '25-11-2026')
      expect(response.parsed_body.dig('data', 'medical_appointment', 'recent_changes', 0, 'reason'))
        .to eq('Candidate cannot reach this centre')
    end

    it 'sends no SMS when the developer unticks it, and clears a field left blank' do
      medical_entry!

      correct(:medical_appointment, { reason: 'Typo', notify_candidate: 'false', center_name: '',
                                      appointment_date: '2026-11-21' })

      expect(response).to have_http_status(:ok)
      expect(candidate_history_details).not_to have_key('medical_center_name')
      expect(CandidateSmsDelivery.count).to eq(0)
    end

    it 'needs a reason and a change' do
      medical_entry!

      correct(:medical_appointment, { center_name: 'New' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('workflow_correction.reason')

      correct(:medical_appointment, { reason: 'Same', center_name: 'Old Centre', appointment_date: '2026-11-20' })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'refuses a bad date or time' do
      medical_entry!

      correct(:medical_appointment, { reason: 'x', appointment_date: '25/11/2026' })
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('workflow_correction.appointment_date')

      correct(:medical_appointment, { reason: 'x', appointment_time: '9.30' })
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('workflow_correction.appointment_time')
    end

    it 'is locked once the candidate is medically fit' do
      medical_entry!
      create(:candidate_medical_result, candidate_assignment: assignment, outcome_code: 'fit')

      correct(:medical_appointment, { reason: 'x', center_name: 'New' })

      expect(response).to have_http_status(:unprocessable_content)
      get base_path, headers: auth_headers(developer)
      expect(response.parsed_body.dig('data', 'medical_appointment'))
        .to include('editable' => false, 'blocked_reason' => 'past_medical')
    end

    it 'stays open for an unfit candidate held at the result stage' do
      medical_entry!
      create(:candidate_medical_result, candidate_assignment: assignment, outcome_code: 'unfit')
      assignment.update!(current_workflow_stage: stage('medical_fit'))

      correct(:medical_appointment, { reason: 'Re-test booked', appointment_date: '2026-12-01' })

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH qvc_appointment' do
    let(:stage_code) { 'qvc_appointment_booked' }
    let!(:attempt) do
      create(:candidate_qvc_attempt, candidate_assignment: assignment, scheduled_by: developer, attempt_number: 1,
                                     appointment_date: Date.new(2026, 12, 1))
    end

    it 'corrects the open booking, and the candidate app sees the new place and time' do
      correct(:qvc_appointment, { reason: 'Rescheduled by QVC', appointment_date: '2026-12-03',
                                  appointment_time: '08:30', center_name: 'QVC Islamabad' })

      expect(response).to have_http_status(:ok)
      expect(attempt.reload).to have_attributes(appointment_date: Date.new(2026, 12, 3), appointment_time: '08:30',
                                                center_name: 'QVC Islamabad')
      qvc = CandidateWorkflows::StateSerializer.new(CandidateWorkflows::StateSnapshotService.call(candidate:))
                                               .as_json[:qvc_attempts].last
      expect(qvc).to include(center_name: 'QVC Islamabad', appointment_time: '08:30')
      expect(CandidateSmsDelivery.find_by!(message_code: 'qvc_appointment_changed').variables)
        .to include('date' => '03-12-2026')
    end

    it 'needs a date and is locked once the QVC result is recorded' do
      correct(:qvc_appointment, { reason: 'x', appointment_date: '' })
      expect(response).to have_http_status(:unprocessable_content)

      attempt.update!(outcome_code: 'approved', outcome_recorded_at: Time.current, outcome_recorded_by: developer)
      correct(:qvc_appointment, { reason: 'x', appointment_date: '2026-12-05' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'message')).to include('QVC result')
    end
  end

  describe 'PATCH flight_detail' do
    let(:stage_code) { 'flight_details_uploaded' }
    let!(:detail) { create(:candidate_flight_detail, candidate_assignment: assignment) }

    it 'corrects the flight, reading the departure as Pakistan time' do
      correct(:flight_detail, { reason: 'Airline changed the flight', airline: 'PIA', flight_number: 'PK-283',
                                sector: '', flight_date: '2026-12-10T14:30' })

      expect(response).to have_http_status(:ok)
      expect(detail.reload).to have_attributes(airline: 'PIA', flight_number: 'PK-283', sector: nil)
      expect(detail.flight_departure_at).to eq(Time.utc(2026, 12, 10, 9, 30))
      expect(CandidateSmsDelivery.find_by!(message_code: 'flight_details_changed').variables)
        .to include('date' => '10-12-2026', 'time' => '14:30')
    end

    it 'replaces the ticket when one is given' do
      correct(:flight_detail, { reason: 'New ticket', airline: detail.airline, flight_number: detail.flight_number,
                                sector: detail.sector, flight_date: detail.flight_departure_at.iso8601,
                                ticket: fixture_file_upload('test.pdf', 'application/pdf') })

      expect(response).to have_http_status(:ok)
      expect(detail.reload.ticket).to be_attached
    end

    it 'is locked once the candidate is mobilized' do
      mobilized_entry = create(:candidate_stage_history, candidate_assignment: assignment,
                                                         to_workflow_stage: stage('mobilized'))
      detail.update!(mobilized_on: detail.flight_departure_at.to_date + 1, mobilized_stage_history: mobilized_entry,
                     mobilized_recorded_by: developer)

      correct(:flight_detail, { reason: 'x', airline: 'PIA', flight_number: 'PK-1', flight_date: '2026-12-10T14:30' })

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
