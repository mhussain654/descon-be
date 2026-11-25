# frozen_string_literal: true

module DocumentChecklists
  # The approved English and Urdu upload instructions shown with each
  # checklist item, as [English, Urdu]. Every document can be a scanned PDF or
  # clear photos (Definitions::CONTENT_TYPES).
  module Instructions
    TEXT = {
      'passport' => [
        'Upload the first two pages of your latest passport: one scanned PDF with both pages, or a clear photo of ' \
        'each page. Scan or photograph in colour, keep each page flat, straight and complete with no edges cut ' \
        'off, and make sure all text is sharp and readable.',
        'اپنے تازہ ترین پاسپورٹ کے پہلے دو صفحات اپ لوڈ کریں: دونوں صفحات کی ایک اسکین شدہ PDF، یا ہر صفحے کی ' \
        'واضح تصویر۔ رنگین اسکین یا تصویر لیں، ہر صفحہ سیدھا اور مکمل ہو، کوئی کنارہ کٹا نہ ہو، اور تمام تحریر ' \
        'واضح اور پڑھنے کے قابل ہو۔'
      ],
      'cnic' => [
        'Upload the front and back of your CNIC: one scanned PDF with both sides, or a clear photo of each side. ' \
        'Scan or photograph in colour, keep the card straight and complete, and make sure all text is sharp and ' \
        'readable.',
        'اپنے شناختی کارڈ کا اگلا اور پچھلا رخ اپ لوڈ کریں: دونوں رخ کی ایک اسکین شدہ PDF، یا ہر رخ کی واضح ' \
        'تصویر۔ رنگین اسکین یا تصویر لیں، کارڈ سیدھا اور مکمل ہو، اور تمام تحریر واضح اور پڑھنے کے قابل ہو۔'
      ],
      'photograph' => [
        'Upload a passport-size photograph as a scanned PDF or a clear photo, as the embassy requires: recent ' \
        '(taken in the last 6 months), in colour, plain blue background, face straight to the camera with eyes ' \
        'open, no glasses, cap or shadows, and your full face and ears clearly visible.',
        'سفارت خانے کی شرائط کے مطابق پاسپورٹ سائز تصویر اسکین شدہ PDF یا واضح تصویر کی صورت میں اپ لوڈ کریں: ' \
        'حالیہ (پچھلے 6 ماہ کی)، رنگین، سادہ نیلا پس منظر، چہرہ سیدھا کیمرے کی طرف اور آنکھیں کھلی ہوں، عینک، ' \
        'ٹوپی یا سایہ نہ ہو، اور پورا چہرہ اور کان صاف نظر آئیں۔'
      ],
      'next_of_kin_cnic' => [
        'Only your father, mother, brother, wife, son, or unmarried sister or daughter can be your Next of Kin. ' \
        'Choose how they are related to you, then upload the front and back of their CNIC: one scanned PDF with ' \
        'both sides, or a clear photo of each side.',
        'صرف آپ کے والد، والدہ، بھائی، بیوی، بیٹا، یا غیر شادی شدہ بہن یا بیٹی آپ کے نیکسٹ آف کن ہو سکتے ہیں۔ ' \
        'بتائیں کہ ان کا آپ سے کیا رشتہ ہے، پھر ان کے شناختی کارڈ کا اگلا اور پچھلا رخ اپ لوڈ کریں: دونوں رخ کی ' \
        'ایک اسکین شدہ PDF، یا ہر رخ کی واضح تصویر۔'
      ],
      'marriage_certificate' => [
        'Your Next of Kin is your wife, so upload your marriage certificate (Nikah Nama) as a scanned PDF or a ' \
        'clear photo.',
        'آپ کی نیکسٹ آف کن آپ کی بیوی ہیں، اس لیے اپنا نکاح نامہ اسکین شدہ PDF یا واضح تصویر کی صورت میں اپ لوڈ کریں۔'
      ],
      'cv' => ['Upload your latest CV as a PDF or a clear photo.',
               'اپنی تازہ ترین سی وی PDF یا واضح تصویر کی صورت میں اپ لوڈ کریں۔'],
      'educational_certificates' => [
        'Upload all your educational certificates as scanned PDFs or clear photos. You can add each certificate ' \
        'as a separate file.',
        'اپنی تمام تعلیمی اسناد اسکین شدہ PDF یا واضح تصاویر کی صورت میں اپ لوڈ کریں۔ ہر سند الگ فائل کے طور پر ' \
        'شامل کی جا سکتی ہے۔'
      ],
      'experience_certificates' => [
        'Upload all your experience certificates as scanned PDFs or clear photos. You can add each certificate ' \
        'as a separate file.',
        'اپنے تمام تجربے کے سرٹیفکیٹس اسکین شدہ PDF یا واضح تصاویر کی صورت میں اپ لوڈ کریں۔ ' \
        'ہر سرٹیفکیٹ الگ فائل کے طور پر شامل کیا جا سکتا ہے۔'
      ],
      'cheque_copy' => [
        'Upload a clear copy of a cheque from your bank account, as a scanned PDF or a clear photo.',
        'اپنے بینک اکاؤنٹ کے چیک کی واضح کاپی اسکین شدہ PDF یا واضح تصویر کی صورت میں اپ لوڈ کریں۔'
      ],
      'gamca_medical_report' => [
        'Upload your GAMCA / Wafid medical report as a PDF or a clear photo.',
        'اپنی GAMCA / وافد میڈیکل رپورٹ PDF یا واضح تصویر کی صورت میں اپ لوڈ کریں۔'
      ],
      'police_character' => [
        'Upload your valid Police Character Certificate as a scanned PDF or a clear photo and enter its issue ' \
        'date. It must have been issued within the last 5 months. The original should be posted to Descon MPS.',
        'اپنا کارآمد پولیس کریکٹر سرٹیفکیٹ اسکین شدہ PDF یا واضح تصویر کی صورت میں اپ لوڈ کریں اور اس کے اجرا کی ' \
        'تاریخ درج کریں۔ یہ پچھلے 5 ماہ کے اندر جاری ہوا ہو۔ اصل سرٹیفکیٹ ڈیسکون ایم پی ایس کو بذریعہ ڈاک بھیجیں۔'
      ],
      'polio_certificate' => [
        'Upload your polio vaccination certificate or card as a PDF or a clear photo.',
        'اپنا پولیو ویکسینیشن سرٹیفکیٹ یا کارڈ PDF یا واضح تصویر کی صورت میں اپ لوڈ کریں۔'
      ],
      'qatar_driving_licence' => [
        'Upload the front and back of your driving licence: one scanned PDF with both sides, or a clear photo of ' \
        'each side.',
        'ڈرائیونگ لائسنس کا اگلا اور پچھلا رخ اپ لوڈ کریں: دونوں رخ کی ایک اسکین شدہ PDF، یا ہر رخ کی واضح تصویر۔'
      ]
    }.freeze
  end
end
