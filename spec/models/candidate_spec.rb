# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidate, type: :model do
  describe 'validations and normalization' do
    it 'is valid with the factory defaults' do
      expect(build(:candidate)).to be_valid
    end

    it 'normalizes CNIC, mobile number, and status code before validation' do
      candidate = build(
        :candidate,
        cnic: '4210112345671',
        mobile_number: '+92 300 123 4567',
        status_code: ' Registered '
      )

      candidate.validate

      expect(candidate.cnic).to eq('42101-1234567-1')
      expect(candidate.mobile_number).to eq('+923001234567')
      expect(candidate.status_code).to eq('registered')
    end

    it 'rejects malformed CNIC input' do
      candidate = build(:candidate, cnic: 'invalid-cnic')

      expect(candidate).not_to be_valid
      expect(candidate.errors[:cnic]).to be_present
    end

    it 'rejects malformed mobile numbers' do
      candidate = build(:candidate, mobile_number: 'abc')

      expect(candidate).not_to be_valid
      expect(candidate.errors[:mobile_number]).to be_present
    end

    it 'normalizes and accepts a complete next-of-kin contact set' do
      candidate = build(
        :candidate,
        next_of_kin_name: '  Ayesha Ali ',
        next_of_kin_relationship: ' Sister ',
        next_of_kin_mobile_number: '+92 300 123 4567',
        next_of_kin_cnic: '4210112345671'
      )

      expect(candidate).to be_valid
      expect(candidate.next_of_kin_mobile_number).to eq('+923001234567')
      expect(candidate.next_of_kin_cnic).to eq('42101-1234567-1')
    end

    it 'rejects an incomplete next-of-kin contact set' do
      candidate = build(:candidate, next_of_kin_name: 'Ayesha Ali')

      expect(candidate).not_to be_valid
      expect(candidate.errors[:next_of_kin_cnic]).to be_present
    end

    it 'rejects malformed status codes' do
      candidate = build(:candidate, status_code: 'Needs Review')

      expect(candidate).not_to be_valid
      expect(candidate.errors[:status_code]).to be_present
    end

    it 'enforces CNIC uniqueness at the application layer' do
      create(:candidate, cnic: '42101-1234567-1')
      duplicate = build(:candidate, cnic: '4210112345671')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:cnic]).to include('has already been taken')
    end

    it 'enforces mobile number uniqueness at the application layer' do
      create(:candidate, mobile_number: '+923001112222')
      duplicate = build(:candidate, mobile_number: '+923001112222')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:mobile_number]).to include('has already been taken')
    end

    it 'rejects concurrent duplicate CNIC inserts at the database layer' do
      create(:candidate, cnic: '42101-1234567-1')

      duplicate = described_class.new(
        full_name: 'Concurrent Candidate',
        cnic: '42101-1234567-1',
        mobile_number: '+923009999999',
        public_id: SecureRandom.uuid,
        preferred_locale: 'en',
        status_code: 'registered',
        active: true,
        source_code: 'csv_import',
        created_by: create(:user)
      )

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'state helpers' do
    it 'returns true for active_for_authentication? only when active' do
      expect(build(:candidate, active: true).active_for_authentication?).to be(true)
      expect(build(:candidate, active: false).active_for_authentication?).to be(false)
    end

    it 'exposes the most recent assignment as the current assignment' do
      candidate = create(:candidate)
      first_assignment = create(:candidate_assignment, candidate:, reference_number: 'DES-000101')
      latest_assignment = create(
        :candidate_assignment,
        candidate:,
        reference_number: 'DES-000102',
        created_at: 1.minute.from_now
      )

      expect(candidate.current_assignment).to eq(latest_assignment)
      expect(candidate.current_assignment).not_to eq(first_assignment)
    end
  end
end
