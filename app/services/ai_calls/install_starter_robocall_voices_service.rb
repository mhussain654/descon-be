# frozen_string_literal: true

module AiCalls
  # The approved RoboCall voices, kept in this one list. Installs each as a call
  # type (so it shows on the Bulk calls page) and points its workflow stage at
  # it. Safe to run again: existing call types and stage voices are never
  # overwritten, so anything an admin has edited stays as they left it, and a
  # stage's call is left switched off -- nothing is called until an admin turns
  # that stage on under "Automatic calls".
  #
  # To add a voice, add one entry here and deploy (or just add it in the admin
  # app -- see docs/deployment/aws-ec2-runbook.md).
  class InstallStarterRobocallVoicesService < ApplicationService
    STARTER_VOICES = [
      { voice_id: '538', name_en: 'Upload documents', name_ur: 'دستاویزات اپ لوڈ کریں',
        stage_code: 'documents_pending' },
      { voice_id: '537', name_en: 'Medical report received', name_ur: 'میڈیکل رپورٹ موصول ہو گئی',
        stage_code: 'medical_completed' },
      { voice_id: '536', name_en: 'Medical date and center added', name_ur: 'میڈیکل کی تاریخ اور مرکز',
        stage_code: 'medical_appointment' }
    ].freeze

    def call
      STARTER_VOICES.each do |entry|
        install_call_type(entry)
        assign_to_stage(entry)
      end
    end

    private

    def install_call_type(entry)
      return if RobocallVoice.exists?(voice_id: entry.fetch(:voice_id))

      RobocallVoice.create!(entry.slice(:voice_id, :name_en, :name_ur))
    end

    def assign_to_stage(entry)
      script = WorkflowStageCallScript.find_or_initialize_by(workflow_stage_code: entry.fetch(:stage_code))
      return if script.voice_id.present?

      script.active = false if script.new_record?
      script.update!(voice_id: entry.fetch(:voice_id))
    end
  end
end
