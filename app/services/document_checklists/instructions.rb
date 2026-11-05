# frozen_string_literal: true

module DocumentChecklists
  # The approved English and Urdu upload instructions shown with each
  # checklist item, as [English, Urdu].
  module Instructions
    TEXT = {
      'passport' => [
        'Upload your latest passport: scan the first two pages into one PDF. Scan in colour, keep each page ' \
        'flat, straight and complete with no edges cut off, and make sure all text is sharp and readable.',
        'اپنا تازہ ترین پاسپورٹ اپ لوڈ کریں: پہلے دو صفحات اسکین کر کے ایک PDF بنائیں۔ رنگین اسکین کریں، ہر صفحہ ' \
        'سیدھا اور مکمل ہو، کوئی کنارہ کٹا نہ ہو، اور تمام تحریر واضح اور پڑھنے کے قابل ہو۔'
      ],
      'cnic' => [
        'Scan the front and back of your CNIC into one PDF. Scan in colour, keep the card straight and complete, ' \
        'and make sure all text is sharp and readable.',
        'اپنے شناختی کارڈ کا اگلا اور پچھلا رخ اسکین کر کے ایک PDF بنائیں۔ رنگین اسکین کریں، کارڈ سیدھا اور مکمل ہو، ' \
        'اور تمام تحریر واضح اور پڑھنے کے قابل ہو۔'
      ],
      'photograph' => [
        'Upload a scanned passport-size photograph as a PDF, as the embassy requires: recent (taken in the last ' \
        '6 months), in colour, plain blue background, face straight to the camera with eyes open, no glasses, ' \
        'cap or shadows, and your full face and ears clearly visible.',
        'سفارت خانے کی شرائط کے مطابق پاسپورٹ سائز تصویر اسکین کر کے PDF میں اپ لوڈ کریں: حالیہ (پچھلے 6 ماہ کی)، ' \
        'رنگین، سادہ نیلا پس منظر، چہرہ سیدھا کیمرے کی طرف اور آنکھیں کھلی ہوں، عینک، ٹوپی یا سایہ نہ ہو، ' \
        'اور پورا چہرہ اور کان صاف نظر آئیں۔'
      ],
      'next_of_kin_cnic' => [
        'Only your father, mother, brother, wife, son, or unmarried sister or daughter can be your Next of Kin. ' \
        'Choose how they are related to you, then scan the front and back of their CNIC into one PDF.',
        'صرف آپ کے والد، والدہ، بھائی، بیوی، بیٹا، یا غیر شادی شدہ بہن یا بیٹی آپ کے نیکسٹ آف کن ہو سکتے ہیں۔ ' \
        'بتائیں کہ ان کا آپ سے کیا رشتہ ہے، پھر ان کے شناختی کارڈ کا اگلا اور پچھلا رخ اسکین کر کے ایک PDF بنائیں۔'
      ],
      'marriage_certificate' => [
        'Your Next of Kin is your wife, so scan your marriage certificate (Nikah Nama) into one PDF.',
        'آپ کی نیکسٹ آف کن آپ کی بیوی ہیں، اس لیے اپنا نکاح نامہ اسکین کر کے ایک PDF بنائیں۔'
      ],
      'cv' => ['Upload your latest CV as a PDF.', 'اپنی تازہ ترین سی وی PDF میں اپ لوڈ کریں۔'],
      'educational_certificates' => [
        'Scan all your educational certificates as PDFs. You can add each certificate as a separate PDF.',
        'اپنی تمام تعلیمی اسناد اسکین کر کے PDF میں اپ لوڈ کریں۔ ہر سند الگ PDF کے طور پر شامل کی جا سکتی ہے۔'
      ],
      'experience_certificates' => [
        'Scan all your experience certificates as PDFs. You can add each certificate as a separate PDF.',
        'اپنے تمام تجربے کے سرٹیفکیٹس اسکین کر کے PDF میں اپ لوڈ کریں۔ ' \
        'ہر سرٹیفکیٹ الگ PDF کے طور پر شامل کیا جا سکتا ہے۔'
      ],
      'cheque_copy' => [
        'Scan a clear copy of a cheque from your bank account into a PDF.',
        'اپنے بینک اکاؤنٹ کے چیک کی واضح کاپی اسکین کر کے PDF میں اپ لوڈ کریں۔'
      ],
      'gamca_medical_report' => [
        'Upload your GAMCA / Wafid medical report as a PDF.',
        'اپنی GAMCA / وافد میڈیکل رپورٹ PDF میں اپ لوڈ کریں۔'
      ],
      'police_character' => [
        'Upload your valid Police Character Certificate as a scanned PDF and enter its issue date. It must have ' \
        'been issued within the last 5 months. The original should be posted to Descon MPS.',
        'اپنا کارآمد پولیس کریکٹر سرٹیفکیٹ اسکین کر کے PDF میں اپ لوڈ کریں اور اس کے اجرا کی تاریخ درج کریں۔ ' \
        'یہ پچھلے 5 ماہ کے اندر جاری ہوا ہو۔ اصل سرٹیفکیٹ ڈیسکون ایم پی ایس کو بذریعہ ڈاک بھیجیں۔'
      ],
      'polio_certificate' => [
        'Upload your polio vaccination certificate or card as a PDF.',
        'اپنا پولیو ویکسینیشن سرٹیفکیٹ یا کارڈ PDF میں اپ لوڈ کریں۔'
      ],
      'qatar_driving_licence' => [
        'Scan the front and back of your driving licence into one PDF.',
        'ڈرائیونگ لائسنس کا اگلا اور پچھلا رخ اسکین کر کے ایک PDF بنائیں۔'
      ]
    }.freeze
  end
end
