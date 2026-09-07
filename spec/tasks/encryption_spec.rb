# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'encryption:verify_candidate_identity_plaintext rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task['encryption:verify_candidate_identity_plaintext'].reenable
  end

  it 'reports OK when every identity field is properly encrypted' do
    create(
      :candidate,
      cnic: '42101-1234567-1',
      passport_number: 'AB1234567',
      next_of_kin_cnic: '42101-7654321-1',
      next_of_kin_name: 'Sister',
      next_of_kin_relationship: 'sibling',
      next_of_kin_mobile_number: '+923001234567'
    )

    expect do
      Rake::Task['encryption:verify_candidate_identity_plaintext'].invoke
    end.to output(/OK: no plaintext found/).to_stdout
  end

  it 'fails and lists the offending public_id when a column still holds plaintext' do
    candidate = create(:candidate, cnic: '42101-1234567-1')
    # update_column still goes through the encrypted attribute's type
    # (encryption is a type-level concern, not a validation/callback), so
    # simulating a genuinely stale plaintext row -- the exact scenario this
    # task exists to catch -- needs a raw SQL write that bypasses the
    # column's type serialization entirely.
    Candidate.connection.execute(
      "UPDATE candidates SET cnic = #{Candidate.connection.quote('42101-1234567-1')} WHERE id = #{candidate.id}"
    )

    expect { Rake::Task['encryption:verify_candidate_identity_plaintext'].invoke }.to raise_error(SystemExit)
  end
end
