# frozen_string_literal: true

# Pre-launch cleanup of all test data (see docs/prelaunch-data-reset.md).
namespace :prelaunch_reset do
  def print_prelaunch_summary(summary, heading)
    puts heading
    summary.table_counts.each { |table, count| puts format('  %-40<table>s %<count>8d', table:, count:) }
    puts "  Stored files of removed records: #{summary.attachment_count}"
    puts "  Staff removed (all but developers): #{summary.removed_staff_count}"
    puts "  Developers kept: #{summary.kept_staff.join(', ').presence || 'none'}"
    puts "  Kept settings will name: #{summary.keeper || 'nobody (no active developer, the run will refuse)'}"
  end

  desc 'Shows what the pre-launch cleanup would delete and keep. Changes nothing.'
  task preview: :environment do
    print_prelaunch_summary(Maintenance::PrelaunchDataReset.preview, 'Would delete (rows per table):')
    puts "\nTo run it: bin/rails prelaunch_reset:run CONFIRM=#{Maintenance::PrelaunchDataReset::CONFIRMATION}"
  end

  desc 'Deletes every candidate, all test activity and all non-developer staff, keeping configuration. ' \
       'Needs CONFIRM=DELETE-ALL-TEST-DATA. Run db:seed afterwards.'
  task run: :environment do
    summary = Maintenance::PrelaunchDataReset.call(confirmation: ENV.fetch('CONFIRM', nil))
    print_prelaunch_summary(summary, 'Deleted (rows per table):')
    puts "\nDone. Now run: bin/rails db:seed (recreates the store reviewer candidate)."
  rescue Maintenance::PrelaunchDataReset::NotAllowedError => e
    abort(e.message)
  end
end
