# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::UpdateService do
  before { ensure_staff_authorization_reference_data! }

  let(:actor) { create(:user, role: 'hr') }
  let(:candidate) { create(:candidate) }
  let!(:assignment) { create(:candidate_assignment, candidate:, registration_number: nil) }

  it 'answers duplicate_registration_number when another save takes the number at the same moment' do
    allow(candidate).to receive(:current_assignment).and_return(assignment)
    allow(assignment).to receive(:save!).and_raise(
      ActiveRecord::RecordNotUnique, 'duplicate key value violates "index_candidate_assignments_on_registration_number"'
    )

    expect { described_class.call(actor:, candidate:, registration_number: '800005') }
      .to raise_error(DuplicateRegistrationNumberError)
  end

  it 're-raises any other unique-index failure' do
    allow(candidate).to receive(:current_assignment).and_return(assignment)
    allow(assignment).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique, 'index_something_else')

    expect { described_class.call(actor:, candidate:, registration_number: '800006') }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
