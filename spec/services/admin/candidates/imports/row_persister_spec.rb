# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::Imports::RowPersister do
  subject(:persister) { described_class.new }

  let(:actor) { create(:user) }
  let(:result) { Admin::Candidates::Imports::Result.new(total_rows: 1) }

  def candidate_attributes(cnic:)
    {
      full_name: 'Jane Doe',
      cnic:,
      mobile_number: '+923001234567',
      preferred_locale: 'en',
      status_code: 'registered',
      active: true,
      source_code: 'csv_import',
      created_by: actor
    }
  end

  def assignment_attributes(reference_number:)
    {
      reference_number:,
      current_workflow_stage: create(:workflow_stage, :registered),
      country: create(:country),
      project: create(:project),
      craft: create(:craft),
      created_by: actor
    }
  end

  def build_row_plan(row_number: 2, cnic: '42101-1234567-1', reference_number: 'DES-000123')
    Admin::Candidates::Imports::Result::RowPlan.new(
      row_number:,
      candidate_attributes: candidate_attributes(cnic:),
      assignment_attributes: assignment_attributes(reference_number:),
      errors: [],
      blank: false
    )
  end

  describe '#call' do
    context 'when the row is new' do
      it 'creates the candidate and assignment and records a success' do
        row_plan = build_row_plan

        expect { persister.call(row_plan:, result:) }
          .to change(Candidate, :count).by(1)
          .and change(CandidateAssignment, :count).by(1)

        expect(result.to_h).to include(successful_rows: 1, failed_rows: 0, skipped_rows: 0)
      end
    end

    context 'when a candidate with the same cnic already exists' do
      it 'skips the row without creating a new candidate' do
        create(:candidate, cnic: '42101-1234567-1', created_by: actor)
        row_plan = build_row_plan(reference_number: 'DES-000999')

        expect { persister.call(row_plan:, result:) }.not_to change(Candidate, :count)

        expect(result.to_h[:errors]).to contain_exactly(
          hash_including(row: 2, field: 'cnic', code: 'duplicate_candidate')
        )
        expect(result.to_h).to include(skipped_rows: 1, successful_rows: 0, failed_rows: 0)
      end
    end

    context 'when an assignment with the same reference number already exists' do
      it 'skips the row without creating a new assignment' do
        existing_candidate = create(:candidate, created_by: actor)
        create(
          :candidate_assignment,
          candidate: existing_candidate,
          reference_number: 'DES-000123',
          created_by: actor
        )
        row_plan = build_row_plan(cnic: '42109-7654321-2')

        expect { persister.call(row_plan:, result:) }.not_to change(CandidateAssignment, :count)

        expect(result.to_h[:errors]).to contain_exactly(
          hash_including(row: 2, field: 'reference_number', code: 'duplicate_reference_number')
        )
        expect(result.to_h).to include(skipped_rows: 1, successful_rows: 0, failed_rows: 0)
      end
    end

    context 'when the database rejects the row as invalid' do
      it 'records a failure instead of raising' do
        row_plan = build_row_plan
        allow(Candidate).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Candidate.new))

        expect { persister.call(row_plan:, result:) }.not_to raise_error

        expect(result.to_h[:errors]).to contain_exactly(
          hash_including(row: 2, field: 'row', code: 'validation_failed')
        )
        expect(result.to_h).to include(failed_rows: 1, successful_rows: 0, skipped_rows: 0)
      end
    end

    context 'when a concurrent request wins the race for the same row' do
      it 'skips the row instead of raising when the unique constraint is violated' do
        row_plan = build_row_plan
        allow(Candidate).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        expect { persister.call(row_plan:, result:) }.not_to raise_error

        expect(result.to_h[:errors]).to contain_exactly(
          hash_including(row: 2, field: 'row', code: 'duplicate_row')
        )
        expect(result.to_h).to include(skipped_rows: 1, successful_rows: 0, failed_rows: 0)
      end
    end
  end
end
