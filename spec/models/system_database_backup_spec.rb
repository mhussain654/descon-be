# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SystemDatabaseBackup do
  it 'is valid with a status code and taken_at' do
    backup = described_class.new(status_code: 'in_progress', taken_at: Time.current)

    expect(backup).to be_valid
  end

  it 'assigns a public_id on creation' do
    backup = create(:system_database_backup)

    expect(backup.public_id).to be_present
  end

  it 'rejects an unsupported status code' do
    backup = described_class.new(status_code: 'bogus', taken_at: Time.current)

    expect(backup).not_to be_valid
    expect(backup.errors[:status_code]).to be_present
  end

  it 'requires taken_at' do
    backup = described_class.new(status_code: 'in_progress', taken_at: nil)

    expect(backup).not_to be_valid
    expect(backup.errors[:taken_at]).to be_present
  end

  it 'can transition from in_progress to succeeded or failed (not an ImmutableRecord)' do
    backup = create(:system_database_backup, status_code: 'in_progress')

    expect { backup.update!(status_code: 'succeeded') }.not_to raise_error
  end

  describe '#succeeded?/#failed?' do
    it 'reflects the status code' do
      expect(build(:system_database_backup, status_code: 'succeeded')).to be_succeeded
      expect(build(:system_database_backup, status_code: 'failed')).to be_failed
      expect(build(:system_database_backup, status_code: 'in_progress')).not_to be_succeeded
    end
  end
end
