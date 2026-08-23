# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidate, type: :model do
  subject(:candidate) { build(:candidate) }

  it { is_expected.to belong_to(:created_by).class_name('User') }
  it { is_expected.to have_many(:candidate_assignments).dependent(:restrict_with_exception) }

  it 'normalizes CNIC, mobile number, and passport number' do
    candidate.cnic = '4210112345671'
    candidate.mobile_number = '+92 300-123 4567'
    candidate.passport_number = ' ab 12345 '
    candidate.validate

    expect(candidate.cnic).to eq('42101-1234567-1')
    expect(candidate.mobile_number).to eq('+923001234567')
    expect(candidate.passport_number).to eq('AB12345')
  end

  it 'validates CNIC uniqueness' do
    existing_candidate = create(:candidate, cnic: '42101-1234567-1')
    duplicate_candidate = build(:candidate, cnic: existing_candidate.cnic)

    expect(duplicate_candidate).not_to be_valid
    expect(duplicate_candidate.errors[:cnic]).to include('has already been taken')
  end

  it 'validates passport uniqueness when present' do
    existing_candidate = create(:candidate, passport_number: 'AB12345')
    duplicate_candidate = build(:candidate, passport_number: existing_candidate.passport_number)

    expect(duplicate_candidate).not_to be_valid
    expect(duplicate_candidate.errors[:passport_number]).to include('has already been taken')
  end

  it 'enforces CNIC uniqueness at the database level' do
    create(:candidate, cnic: '42101-1234567-1')

    expect do
      described_class.connection.exec_insert(
        <<~SQL.squish,
          INSERT INTO candidates (
            public_id,
            full_name,
            cnic,
            mobile_number,
            preferred_locale,
            source_code,
            created_by_id,
            created_at,
            updated_at
          )
          VALUES (
            #{described_class.connection.quote(SecureRandom.uuid)},
            'Duplicate Candidate',
            '42101-1234567-1',
            '+923001111111',
            'en',
            'admin_ui',
            #{create(:user).id},
            #{described_class.connection.quote(Time.current)},
            #{described_class.connection.quote(Time.current)}
          )
        SQL
        'SQL'
      )
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'returns representative English validation messages' do
    candidate.cnic = 'invalid'
    candidate.mobile_number = 'bad'
    candidate.valid?

    expect(candidate.errors.full_messages).to include(
      'Cnic is not in the required format.',
      'Mobile number is not in the required format.'
    )
  end

  it 'returns representative Urdu validation messages' do
    candidate.cnic = 'invalid'
    candidate.mobile_number = 'bad'

    I18n.with_locale(:ur) do
      candidate.valid?
      expect(candidate.errors.full_messages).to include(
        'شناختی کارڈ نمبر مطلوبہ فارمیٹ میں نہیں ہے۔',
        'موبائل نمبر مطلوبہ فارمیٹ میں نہیں ہے۔'
      )
    end
  end
end
