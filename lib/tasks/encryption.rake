# frozen_string_literal: true

namespace :encryption do
  desc 'Verifies no plaintext remains in candidates.cnic/next_of_kin_cnic/passport_number ' \
       '(MPS-901). Exits non-zero and lists offending public_ids if any row still looks like ' \
       'plaintext -- run this before disabling ' \
       'config.active_record.encryption.support_unencrypted_data.'
  task verify_candidate_identity_plaintext: :environment do
    columns = %w[cnic next_of_kin_cnic passport_number]
    offending = columns.index_with { [] }

    Candidate.unscoped.select(:id, :public_id, *columns).find_each do |candidate|
      columns.each do |column|
        raw_value = candidate.read_attribute_before_type_cast(column)
        offending[column] << candidate.public_id if raw_value.present? && !ciphertext?(raw_value)
      end
    end

    total = offending.values.sum(&:size)
    if total.zero?
      puts 'OK: no plaintext found in candidates.cnic/next_of_kin_cnic/passport_number.'
    else
      offending.each do |column, public_ids|
        puts "#{column}: #{public_ids.size} plaintext row(s) -- #{public_ids.join(', ')}" unless public_ids.empty?
      end
      abort("FAILED: #{total} row(s) still hold plaintext -- do not disable support_unencrypted_data yet.")
    end
  end
end

# Active Record Encryption's ciphertext envelope is a JSON object shaped
# like {"p"=>"...", "h"=>{"iv"=>"...", "at"=>"..."}} (confirmed directly
# against a real encrypted column's raw stored value, not assumed) --
# anything that doesn't parse as JSON with a "p" key is plaintext.
def ciphertext?(raw_value)
  parsed = JSON.parse(raw_value)
  parsed.is_a?(Hash) && parsed.key?('p')
rescue JSON::ParserError
  false
end
