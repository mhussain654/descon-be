# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260914090000_add_unique_index_to_candidates_mobile_number')

RSpec.describe AddUniqueIndexToCandidatesMobileNumber do
  subject(:migration) { described_class.new }

  # This migration's schema change (add_index/remove_index) is already
  # applied to the shared test database via schema.rb, so #up cannot be
  # re-run end-to-end here without erroring on an already-existing index --
  # that path is exercised once, directly, via `rails db:migrate`/
  # `db:rollback:primary` (see PR notes). What's actually worth unit-testing
  # is the duplicate-detection guard, since it runs and raises before any
  # schema change is attempted -- exercised safely regardless of the
  # database's current migration state.
  describe '#up' do
    # The unique index this migration adds is already applied to this test
    # database (see schema.rb), which now makes a real duplicate
    # mobile_number row impossible to create here -- exactly the end state
    # this migration is meant to reach. Stubbing the duplicate-detection
    # query is the only way left to exercise its error-raising and
    # message-formatting logic against a database in that end state.
    it 'refuses to run when duplicate mobile numbers exist, naming the colliding candidate id' do
      candidate = create(:candidate)
      # rubocop:disable RSpec/SubjectStub -- the unique index already applied
      # to this test database makes a real duplicate un-creatable; stubbing
      # the query is the only way left to exercise the guard's raise path.
      allow(migration).to receive(:duplicated_mobile_numbers).and_return([candidate.mobile_number])
      # rubocop:enable RSpec/SubjectStub

      expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /#{candidate.id}/)
    end

    it 'does not raise the duplicate-detection guard when no duplicates exist' do
      create(:candidate)
      create(:candidate)

      expect { migration.send(:refuse_if_duplicates_exist!) }.not_to raise_error
    end
  end
end
