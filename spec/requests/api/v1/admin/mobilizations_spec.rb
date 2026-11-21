# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Mobilizations', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  let(:path) { '/api/v1/admin/mobilizations' }

  def staff_headers(role: 'admin')
    user = create(:user, role:)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def flight_for(name, departure: 1.week.from_now, uploaded: false, mobilized: false, flight_number: 'QR-123')
    candidate = create(:candidate, full_name: name)
    assignment = create(:candidate_assignment, candidate:)
    create(:candidate_flight_detail, *([:mobilized] if mobilized),
           candidate_assignment: assignment, flight_departure_at: departure, flight_number:,
           boarding_pass_uploaded_at: (Time.current if uploaded))
  end

  def names
    response.parsed_body.fetch('data').map { |row| row.dig('candidate', 'full_name') }
  end

  describe 'GET /api/v1/admin/mobilizations' do
    it 'lists only candidates with a recorded flight, with their flight, ticket, boarding pass and status' do
      travel_to Time.utc(2026, 11, 21, 6, 0)
      detail = flight_for('Booked Candidate', departure: Time.utc(2026, 12, 1, 9, 30), uploaded: true)
      create(:candidate_assignment, candidate: create(:candidate, full_name: 'No Flight Yet'))

      get path, headers: staff_headers

      expect(response).to have_http_status(:ok)
      row = response.parsed_body.fetch('data').sole
      expect(row).to include(
        'id' => detail.public_id, 'airline' => 'Qatar Airways', 'flight_number' => 'QR-123', 'sector' => 'LHE-DOH',
        'flight_departure_at' => '2026-12-01T09:30:00Z', 'ticket_attached' => false,
        'boarding_pass_uploaded_at' => detail.boarding_pass_uploaded_at.utc.iso8601,
        'mobilized_on' => nil, 'status' => 'scheduled'
      )
      expect(row.fetch('candidate')).to include('id' => detail.candidate_assignment.candidate.public_id,
                                                'full_name' => 'Booked Candidate',
                                                'reference_number' => detail.candidate_assignment.reference_number)
      expect(response.parsed_body.dig('meta', 'pagination', 'total_count')).to eq(1)
    end

    it "shows one day's flights in Pakistan time, filterable by boarding pass, with counts for each option" do
      travel_to Time.utc(2026, 11, 20, 3, 0) # 08:00 on 20 Nov in Pakistan
      # 02:00 on 20 Nov in Pakistan is 21:00 UTC on 19 Nov.
      flight_for('Early Uploaded', departure: Time.utc(2026, 11, 19, 21, 0), uploaded: true)
      flight_for('Evening Missing', departure: Time.utc(2026, 11, 20, 18, 30))
      flight_for('Next Day In Pakistan', departure: Time.utc(2026, 11, 20, 19, 30))
      headers = staff_headers

      get path, params: { filter: { flight_date: '2026-11-20' }, sort: 'departure_at' }, headers: headers

      expect(names).to eq(['Early Uploaded', 'Evening Missing'])
      expect(response.parsed_body.dig('meta', 'summary')).to eq(
        'total' => 2, 'boarding_pass' => { 'uploaded' => 1, 'missing' => 1 },
        'status' => { 'scheduled' => 0, 'departing_today' => 2, 'departed' => 0, 'not_confirmed' => 0 }
      )

      get path, params: { filter: { flight_date: '2026-11-20', boarding_pass: 'missing' } }, headers: headers
      expect(names).to eq(['Evening Missing'])
      expect(response.parsed_body.dig('meta', 'summary', 'boarding_pass')).to eq('uploaded' => 1, 'missing' => 1)
    end

    describe 'the departure status' do
      # 10:00 on 21 Nov in Pakistan.
      before { travel_to Time.utc(2026, 11, 21, 5, 0) }

      let!(:flights) do
        {
          later: flight_for('Flies Tomorrow', departure: Time.utc(2026, 11, 21, 19, 30)), # 00:30 on 22 Nov PKT
          today: flight_for('Flies Tonight', departure: Time.utc(2026, 11, 21, 18, 30), uploaded: true),
          confirmed: flight_for('Confirmed By Staff', departure: Time.utc(2026, 11, 10, 8, 0), mobilized: true),
          checked_in: flight_for('Boarding Pass After Flight', departure: Time.utc(2026, 11, 20, 3, 0), uploaded: true),
          unknown: flight_for('No Word Since', departure: Time.utc(2026, 11, 20, 18, 0)), # 23:00 on 20 Nov PKT
          doubtful: needs_review(flight_for('Photo Needs A Look', departure: Time.utc(2026, 11, 20, 3, 0),
                                                                  uploaded: true))
        }
      end
      let(:headers) { staff_headers }

      def needs_review(detail)
        detail.tap { |record| record.update!(boarding_pass_check: 'needs_review', boarding_pass_seat: '12F') }
      end

      def statuses
        response.parsed_body.fetch('data').to_h { |row| [row.dig('candidate', 'full_name'), row.fetch('status')] }
      end

      it 'follows the flight day in Pakistan, and counts a past flight with a boarding pass as departed' do
        get path, headers: headers

        expect(statuses).to eq(
          'Flies Tomorrow' => 'scheduled', 'Flies Tonight' => 'departing_today',
          'Confirmed By Staff' => 'departed', 'Boarding Pass After Flight' => 'departed',
          'No Word Since' => 'not_confirmed', 'Photo Needs A Look' => 'not_confirmed'
        )
        doubtful_row = response.parsed_body['data'].find { |row| row['id'] == flights[:doubtful].public_id }
        expect(doubtful_row).to include('boarding_pass_rejected' => false)
        expect(doubtful_row['boarding_pass_check']).to include('result' => 'needs_review', 'seat' => '12F')
        confirmed_row = response.parsed_body['data'].find { |row| row['id'] == flights[:confirmed].public_id }
        expect(confirmed_row).to include('mobilized_on' => flights[:confirmed].mobilized_on.iso8601)
        expect(response.parsed_body.dig('meta', 'summary', 'status'))
          .to eq('scheduled' => 1, 'departing_today' => 1, 'departed' => 2, 'not_confirmed' => 2)
      end

      it 'filters by each status with the same rule' do
        { 'scheduled' => ['Flies Tomorrow'], 'departing_today' => ['Flies Tonight'],
          'departed' => ['Boarding Pass After Flight', 'Confirmed By Staff'],
          'not_confirmed' => ['No Word Since', 'Photo Needs A Look'] }.each do |status, expected|
          get path, params: { filter: { status: }, sort: 'departure_at' }, headers: headers
          expect(names).to match_array(expected), "filter[status]=#{status}"
        end
      end
    end

    it 'searches by candidate name, reference number or flight number' do
      flight_for('Ali Raza', flight_number: 'PK-781')
      other = flight_for('Bilal Khan', flight_number: 'EK-600')
      headers = staff_headers

      get path, params: { search: 'raza' }, headers: headers
      expect(names).to eq(['Ali Raza'])

      get path, params: { search: 'ek-600' }, headers: headers
      expect(names).to eq(['Bilal Khan'])

      get path, params: { search: other.candidate_assignment.reference_number.downcase }, headers: headers
      expect(names).to eq(['Bilal Khan'])
    end

    it "shows only the current assignment's flight for a candidate whose process restarted" do
      old = flight_for('Restarted Candidate')
      create(:candidate_assignment, candidate: old.candidate_assignment.candidate, created_at: 1.minute.from_now)

      get path, headers: staff_headers

      expect(names).to be_empty
    end

    it 'sorts by departure, newest first by default' do
      flight_for('Sooner', departure: 1.day.from_now)
      flight_for('Later', departure: 3.days.from_now)
      headers = staff_headers

      get path, headers: headers
      expect(names).to eq(%w[Later Sooner])

      get path, params: { sort: 'departure_at' }, headers: headers
      expect(names).to eq(%w[Sooner Later])
    end

    it 'rejects invalid filters, sorts and page sizes' do
      headers = staff_headers

      get path, params: { filter: { flight_date: '20/11/2026' } }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.flight_date')

      get path, params: { filter: { boarding_pass: 'sometimes' } }, headers: headers
      expect(response).to have_http_status(:bad_request)

      get path, params: { filter: { status: 'flying' } }, headers: headers
      expect(response).to have_http_status(:bad_request)

      get path, params: { filter: { project_code: 'qatar' } }, headers: headers
      expect(response).to have_http_status(:bad_request)

      get path, params: { sort: 'full_name' }, headers: headers
      expect(response).to have_http_status(:bad_request)

      get path, params: { page: { size: 101 } }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it 'narrows to one import batch by registered date (Pakistan time) and country' do
      country = create(:country)
      batch = flight_for('Batch Candidate')
      batch.candidate_assignment.update!(country:)
      # 01:00 on 20 Nov in Pakistan is 20:00 UTC on 19 Nov.
      batch.candidate_assignment.candidate.update!(created_at: Time.utc(2026, 11, 19, 20, 0))
      other_day = flight_for('Other Batch')
      other_day.candidate_assignment.update!(country:)
      other_day.candidate_assignment.candidate.update!(created_at: Time.utc(2026, 11, 28, 6, 0))
      flight_for('Other Country').candidate_assignment.candidate.update!(created_at: Time.utc(2026, 11, 20, 6, 0))
      headers = staff_headers

      get path, params: { filter: { registered_from: '2026-11-20', registered_to: '2026-11-20',
                                    country_code: country.code } }, headers: headers

      expect(names).to eq(['Batch Candidate'])

      get path, params: { filter: { country_code: 'atlantis' } }, headers: headers
      expect(response).to have_http_status(:bad_request)

      get path, params: { filter: { registered_from: '2026-11-21', registered_to: '2026-11-20' } }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.registered_to')
    end

    it 'paginates' do
      3.times { |index| flight_for("Candidate #{index}", departure: (index + 1).days.from_now) }

      get path, params: { page: { number: 2, size: 2 } }, headers: staff_headers

      expect(names.size).to eq(1)
      expect(response.parsed_body.dig('meta', 'pagination')).to include('page' => 2, 'per_page' => 2,
                                                                        'total_count' => 3, 'total_pages' => 2)
    end

    it 'forbids staff without permission to view candidates' do
      RolePermission.joins(:role, :permission)
                    .where(roles: { code: 'finance' }, permissions: { code: %w[view_candidates manage_candidates] })
                    .destroy_all

      get path, headers: staff_headers(role: 'finance')

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get path

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
