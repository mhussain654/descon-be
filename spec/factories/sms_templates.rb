# frozen_string_literal: true

FactoryBot.define do
  factory :sms_template do
    message_code { 'registered' }
    template_id_en { '20001' }
    template_id_ur { nil }
    enabled { true }
  end
end
