# frozen_string_literal: true

# A Pakistani IBAN: "PK", two check digits, the bank's 4-letter code and a
# 16-digit account number (24 characters), whose check digits pass the
# ISO 13616 mod-97 test. Client rule: candidates give their full IBAN, not a
# plain account number.
module PakistanIban
  FORMAT = /\APK\d{2}[A-Z]{4}\d{16}\z/

  module_function

  # `value` is already normalized (upper case, no spaces).
  def valid?(value)
    value = value.to_s
    FORMAT.match?(value) && checksum_valid?(value)
  end

  def checksum_valid?(value)
    rearranged = value[4..] + value[0, 4]
    digits = rearranged.chars.map { |char| char.match?(/\d/) ? char : (char.ord - 55).to_s }.join
    (digits.to_i % 97) == 1
  end
end
