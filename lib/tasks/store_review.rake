# frozen_string_literal: true

namespace :store_review do
  desc 'Creates the Google Play / App Store reviewer demo candidate at Enrolled (needs store_review cnic and ' \
       'otp_code in the encrypted credentials). Pass the email of the staff user recorded as its creator.'
  task :create_candidate, [:created_by_email] => :environment do |_task, args|
    created_by = User.find_by(email: args[:created_by_email].to_s.strip.downcase)
    abort('Pass an existing staff user email: rails "store_review:create_candidate[admin@example.com]"') unless
      created_by

    candidate = StoreReview::CreateCandidateService.call(created_by:)
    stage = candidate.current_assignment.current_workflow_stage.code
    puts "Store reviewer candidate #{candidate.public_id} is at #{stage}."
  rescue StoreReview::CreateCandidateService::NotConfiguredError => e
    abort(e.message)
  end
end
