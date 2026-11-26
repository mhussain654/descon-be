# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maintenance::PrelaunchDataReset do
  before { ensure_staff_authorization_reference_data! }

  let!(:developer) { create(:user, role: 'developer') }
  let(:admin) { create(:user, role: 'admin') }
  let(:confirmation) { described_class::CONFIRMATION }

  def create_training_video(owner)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("\0\0\0\x18ftypisom".b), filename: 'a.mp4',
                                                  content_type: 'video/mp4')
    TrainingVideo.new(title_en: 'A', title_ur: 'ا', position: 0, created_by: owner).tap do |video|
      video.file.attach(blob)
      video.save!
    end
  end

  describe '.call' do
    it 'removes candidates, their activity and files, and non-developer staff, keeping configuration' do
      document_blob_id = create(:candidate_document).files.first.file.blob.id
      create(:payment)
      create(:audit_event)
      create(:session, user: admin)
      support_setting = SupportSetting.current.tap { |setting| setting.update_column(:updated_by_id, admin.id) } # rubocop:disable Rails/SkipsModelValidations
      video = create_training_video(admin)
      country_count = Country.count

      described_class.call(confirmation:)

      expect([Candidate, CandidateAssignment, CandidateDocument, CandidateDocumentFile, Payment, AuditEvent, Session]
               .map(&:count)).to all(eq(0))
      expect(User.pluck(:id)).to eq([developer.id])
      expect(ActiveStorage::Blob.exists?(document_blob_id)).to be(false)
      expect(support_setting.reload.updated_by_id).to eq(developer.id)
      expect(video.reload.created_by_id).to eq(developer.id)
      expect(video.file).to be_attached
      expect(Country.count).to eq(country_count)
    end

    it 'keeps every developer, naming the earliest active one on kept settings' do
      later_developer = create(:user, role: 'developer', invited_by: admin)
      create_training_video(admin)

      described_class.call(confirmation:)

      expect(User.order(:created_at).pluck(:id)).to eq([developer.id, later_developer.id])
      expect(later_developer.reload.invited_by_id).to be_nil
      expect(TrainingVideo.pluck(:created_by_id)).to eq([developer.id])
    end

    it 'removes campaigns made while testing but keeps the Test campaign' do
      campaign = create(:campaign)
      admin.update!(selected_campaign: campaign)
      developer.update!(selected_campaign: campaign)

      expect(described_class.preview.table_counts.fetch('campaigns')).to eq(Campaign.regular.count)
      described_class.call(confirmation:)

      expect(Campaign.regular).to be_empty
      expect(Campaign.test_campaign).to be_present
      expect(developer.reload.selected_campaign_id).to be_nil
    end

    it 'refuses without the confirmation word, deleting nothing' do
      create(:candidate)

      expect { described_class.call(confirmation: 'yes') }.to raise_error(described_class::NotAllowedError)
      expect(Candidate.count).to be_positive
    end

    it 'refuses when no active developer would remain' do
      developer.update!(active: false)
      create(:candidate)

      expect { described_class.call(confirmation:) }.to raise_error(described_class::NotAllowedError, /developer/)
      expect(Candidate.count).to be_positive
    end
  end

  describe '.preview' do
    it 'reports what a run would delete and keep, changing nothing' do
      create(:candidate_document)
      admin

      summary = described_class.preview

      expect(summary.table_counts.fetch('candidates')).to eq(Candidate.count)
      expect(summary.removed_staff_count).to eq(User.where.not(role: 'developer').count)
      expect(summary.kept_staff).to eq([developer.email])
      expect(summary.keeper).to eq(developer.email)
      expect(summary.attachment_count).to be_positive
      expect(Candidate.count).to be_positive
    end
  end

  # Guards for tables added later: each must be either purged or kept on purpose.
  describe 'table coverage' do
    let(:reset) { described_class.new }
    let(:tables) { ActiveRecord::Base.connection.tables }

    it 'orders every purged table, and every one exists' do
      expect(reset.ordered_tables).to match_array(described_class::PURGED_TABLES)
      expect(described_class::PURGED_TABLES - tables).to be_empty
    end

    it 'leaves no kept table pointing at a purged one' do
      expect(reset.kept_tables_referencing_purged).to be_empty
    end

    it 'purges every table that belongs to a candidate or assignment' do
      candidate_owned = tables.select do |table|
        columns = ActiveRecord::Base.connection.columns(table).map(&:name)
        columns.intersect?(%w[candidate_id candidate_assignment_id])
      end

      expect(candidate_owned - described_class::PURGED_TABLES).to be_empty
    end
  end
end
