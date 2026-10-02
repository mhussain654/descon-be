# frozen_string_literal: true

namespace :mobilization do
  desc 'Attach assignments created before mobilization processes existed to their country process'
  task backfill_processes: :environment do
    result = MobilizationProcesses::AssignmentBackfill.call
    puts "Linked #{result.linked_count} assignment(s) to a mobilization process."
    next if result.unmatched_reference_numbers.empty?

    puts 'Current stage not in the resolved process (left unlinked): ' \
         "#{result.unmatched_reference_numbers.join(', ')}"
  end
end
