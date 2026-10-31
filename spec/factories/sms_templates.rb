# frozen_string_literal: true

FactoryBot.define do
  # One row per message: the migration that creates the table also fills it, so
  # a migrated (rather than schema-loaded) database already has every row. The
  # factory reuses that row instead of inserting a duplicate.
  factory :sms_template do
    initialize_with { SmsTemplate.find_or_initialize_by(message_code:) }

    message_code { 'registered' }
    template_id_en { '20001' }
    template_id_ur { nil }
    enabled { true }
  end
end
