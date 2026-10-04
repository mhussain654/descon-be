# frozen_string_literal: true

module DocumentChecklists
  # The approved English and Urdu upload instructions shown with each
  # checklist item, as [English, Urdu].
  module Instructions
    TEXT = {
      'passport' => [
        'Upload the first two pages of your passport as one PDF, or as two photos labelled page 1 and page 2.',
        'پاسپورٹ کے پہلے دو صفحات ایک PDF میں، یا دو تصاویر (صفحہ 1 اور صفحہ 2) کی صورت میں اپ لوڈ کریں۔'
      ],
      'cnic' => [
        'Upload the front and back of your CNIC as one PDF, or as two photos labelled front and back.',
        'شناختی کارڈ کا اگلا اور پچھلا رخ ایک PDF میں، یا دو تصاویر (اگلا رخ اور پچھلا رخ) کی صورت میں اپ لوڈ کریں۔'
      ],
      'photograph' => [
        'Upload a recent photograph of yourself with a plain blue background.',
        'نیلے پس منظر والی اپنی حالیہ تصویر اپ لوڈ کریں۔'
      ],
      'next_of_kin_cnic' => [
        "Upload the front and back of your legal heir's CNIC as one PDF, or as two photos labelled front and back.",
        'قانونی وارث کے شناختی کارڈ کا اگلا اور پچھلا رخ ایک PDF میں، یا دو تصاویر کی صورت میں اپ لوڈ کریں۔'
      ],
      'cv' => ['Upload your latest CV.', 'اپنی تازہ ترین سی وی اپ لوڈ کریں۔'],
      'educational_certificates' => [
        'Upload all your educational certificates. You can add each certificate as a separate file.',
        'اپنی تمام تعلیمی اسناد اپ لوڈ کریں۔ ہر سند الگ فائل کے طور پر شامل کی جا سکتی ہے۔'
      ],
      'experience_certificates' => [
        'Upload all your experience certificates. You can add each certificate as a separate file.',
        'اپنے تمام تجربے کے سرٹیفکیٹس اپ لوڈ کریں۔ ہر سرٹیفکیٹ الگ فائل کے طور پر شامل کیا جا سکتا ہے۔'
      ],
      'cheque_copy' => [
        'Upload a clear copy of a cheque from your bank account.',
        'اپنے بینک اکاؤنٹ کے چیک کی واضح کاپی اپ لوڈ کریں۔'
      ],
      'gamca_medical_report' => [
        'Upload your GAMCA / Wafid medical report.',
        'اپنی GAMCA / وافد میڈیکل رپورٹ اپ لوڈ کریں۔'
      ],
      'police_character' => [
        'Upload your Police Character Certificate and enter its issue date.',
        'اپنا پولیس کریکٹر سرٹیفکیٹ اپ لوڈ کریں اور اس کے اجرا کی تاریخ درج کریں۔'
      ],
      'polio_certificate' => [
        'Upload your polio vaccination certificate or card.',
        'اپنا پولیو ویکسینیشن سرٹیفکیٹ یا کارڈ اپ لوڈ کریں۔'
      ],
      'qatar_driving_licence' => [
        'Upload the front and back of your driving licence as one PDF, or as two photos labelled front and back.',
        'ڈرائیونگ لائسنس کا اگلا اور پچھلا رخ ایک PDF میں، یا دو تصاویر کی صورت میں اپ لوڈ کریں۔'
      ]
    }.freeze
  end
end
