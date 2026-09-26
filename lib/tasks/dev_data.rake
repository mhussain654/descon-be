# frozen_string_literal: true

def print_qa_seed_counts(candidates)
  puts "  #{candidates.size} candidates across #{DevData::QaDataSeeder::STAGE_CODES.size} workflow stages"
  puts "  #{candidates.count { |c| c.fetch(:profile).ai_call }} AI calls"
  puts "  #{Payment.count} payments, #{CandidateVisaDecision.count} visa decisions, " \
       "#{CandidateQvcAttempt.count} QVC attempts, #{CandidateProtectionRecord.count} protection records, " \
       "#{CandidateFlightDetail.count} flight details"
  puts "  #{AuditEvent.count} audit events, #{Communication.count} communications"
end

def print_qa_seed_login_hint
  puts "\nLog in as any seeded staff user with password '#{DevData::QaDataSeeder::PASSWORD}', e.g.:"
  %w[admin hr mps finance management].each { |role| puts "  qa-#{role}1@descon.local" }
end

def print_qa_seed_summary(candidates)
  puts "\nDone. Created:"
  print_qa_seed_counts(candidates)
  print_qa_seed_login_hint
end

def run_qa_seed_task
  require Rails.root.join('lib/dev_data/qa_data_seeder')
  puts "Seeding #{DevData::QaDataSeeder::PROFILES.size} QA candidates across every workflow stage..."
  print_qa_seed_summary(DevData::QaDataSeeder.call)
rescue RuntimeError => e
  abort(e.message)
end

def run_qa_clear_task
  require Rails.root.join('lib/dev_data/qa_data_clearer')
  cleared_count = DevData::QaDataClearer.call
  cleared_count.zero? ? puts('No QA seed data found.') : puts("Cleared QA seed data (#{cleared_count} candidates).")
rescue RuntimeError => e
  abort(e.message)
end

namespace :dev_data do
  desc 'Seeds ~25 candidates spread across every workflow stage, plus documents, QVC/visa/' \
       'protection/flight/payment records, AI calls, communications, audit events, document ' \
       'submissions, an import batch, and database backups -- enough to manually exercise every ' \
       'admin tab and filter combination. Development-only; refuses to run elsewhere.'
  task seed_qa_data: :environment do
    run_qa_seed_task
  end

  desc 'Removes everything dev_data:seed_qa_data created. Development-only.'
  task clear_qa_data: :environment do
    run_qa_clear_task
  end
end
