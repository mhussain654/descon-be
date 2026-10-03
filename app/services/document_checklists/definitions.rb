# frozen_string_literal: true

module DocumentChecklists
  # The approved document catalog and per-country checklists, reviewed
  # through PRs rather than built in an admin UI (first release). The common
  # checklist applies to every country; KSA and Qatar add their confirmed
  # documents. The five provisional countries (UAE, Oman, Kuwait, Azerbaijan,
  # South Africa) get the common checklist only.
  module Definitions
    CONTENT_TYPES = %w[application/pdf image/jpeg image/png].freeze

    # How each kind of document is uploaded.
    UPLOAD_PROFILES = {
      single: { minimum_files: 1, maximum_files: 1, combined_pdf_allowed: false, allowed_side_codes: [] },
      photo: { minimum_files: 1, maximum_files: 1, combined_pdf_allowed: false, allowed_side_codes: [],
               accepted_content_types: %w[image/jpeg image/png] },
      two_pages: { minimum_files: 1, maximum_files: 2, combined_pdf_allowed: true,
                   allowed_side_codes: %w[combined page_1 page_2] },
      two_sided: { minimum_files: 1, maximum_files: 2, combined_pdf_allowed: true,
                   allowed_side_codes: %w[combined front back] },
      certificates: { minimum_files: 1, maximum_files: 10, combined_pdf_allowed: false,
                      allowed_side_codes: %w[certificate] }
    }.freeze

    DOCUMENT_TYPES = [
      { code: 'passport', name_en: 'Passport', name_ur: 'پاسپورٹ', requires_number: true, requires_expiry: true },
      { code: 'cnic', name_en: 'CNIC', name_ur: 'شناختی کارڈ', requires_expiry: true },
      { code: 'photograph', name_en: 'Photograph (Blue Background)', name_ur: 'تصویر (نیلا پس منظر)' },
      { code: 'next_of_kin_cnic', name_en: 'Legal Heir / Next of Kin CNIC',
        name_ur: 'قانونی وارث / قریبی رشتہ دار کا شناختی کارڈ', requires_expiry: true },
      { code: 'cv', name_en: 'CV / Resume', name_ur: 'سی وی / ریزیومے' },
      { code: 'educational_certificates', name_en: 'Educational Certificates', name_ur: 'تعلیمی اسناد' },
      { code: 'experience_certificates', name_en: 'Experience Certificates', name_ur: 'تجربے کے سرٹیفکیٹس' },
      { code: 'cheque_copy', name_en: 'Cheque Copy', name_ur: 'چیک کی کاپی' },
      { code: 'gamca_medical_report', name_en: 'GAMCA / Wafid Medical Report',
        name_ur: 'GAMCA / وافد میڈیکل رپورٹ' },
      { code: 'police_character', name_en: 'Police Character Certificate', name_ur: 'پولیس کریکٹر سرٹیفکیٹ',
        requires_expiry: true },
      { code: 'polio_certificate', name_en: 'Polio Certificate / Card', name_ur: 'پولیو سرٹیفکیٹ / کارڈ' },
      { code: 'qatar_driving_licence', name_en: 'Qatar Driving Licence', name_ur: 'قطر ڈرائیونگ لائسنس',
        requires_expiry: true }
    ].freeze

    # Superseded codes from the single-file checklist: kept (inactive) because
    # existing documents may reference them, never offered again.
    RETIRED_DOCUMENT_TYPE_CODES = %w[cnic_front cnic_back experience_letter certificates cheque_image
                                     bank_details].freeze

    # [document code, upload profile, extra attributes] in display order.
    COMMON = [
      ['passport', :two_pages], ['cnic', :two_sided], ['photograph', :photo], ['next_of_kin_cnic', :two_sided],
      ['cv', :single], ['educational_certificates', :certificates], ['experience_certificates', :certificates],
      ['cheque_copy', :single]
    ].freeze

    COUNTRY_ADDITIONS = {
      'saudi_arabia' => [['gamca_medical_report', :single]],
      'qatar' => [
        ['police_character', :single], ['polio_certificate', :single],
        ['qatar_driving_licence', :two_sided, { driver_only: true }]
      ]
    }.freeze

    module_function

    # Every requirement row: { document_code:, country_code:, attributes: }.
    def requirements
      rows = COMMON.each_with_index.map { |entry, index| requirement_row(entry, nil, index + 1) }
      COUNTRY_ADDITIONS.each do |country_code, entries|
        entries.each_with_index do |entry, index|
          rows << requirement_row(entry, country_code, COMMON.size + index + 1)
        end
      end
      rows
    end

    def requirement_row((document_code, profile, extra), country_code, display_position)
      instructions_en, instructions_ur = Instructions::TEXT.fetch(document_code)
      attributes = { accepted_content_types: CONTENT_TYPES }.merge(UPLOAD_PROFILES.fetch(profile)).merge(
        requirement_level: 'required', display_position:, instructions_en:, instructions_ur:,
        driver_only: false, active: true
      ).merge(extra || {})
      { document_code:, country_code:, attributes: }
    end
  end
end
