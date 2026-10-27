# RoboCall voice recordings

The fixed recordings RoboCall plays for automatic and bulk calls. We send only the
candidate's number and the voice ID, so the audio lives in the RoboCall account, not
in this repository. The same recording is played to English and Urdu candidates.

The wording below was **machine-transcribed** (Google speech recognition) from the
approved audio files on 2026-10-20. Company and app names were often misheard, so
treat it as a guide to the content and check the exact wording against the audio.

| Voice ID | RoboCall name | Call type (admin app) | Workflow stage it is set on |
|---|---|---|---|
| 538 | descon-engineering-upload-document | Upload documents | `documents_pending` (all countries) |
| 537 | descon-engineering-medical-report-received | Medical report received | `medical_fit` (Qatar process) |
| 536 | Descon-engineering-medical-date-update | Medical date and center added | `medical_appointment` (Qatar process) |

A call is placed when a candidate moves into the stage, once per candidate per stage.
On a medical-result stage (such as `medical_fit`) it is placed only when the result is
fit: an unfit candidate is held at that stage and gets no automatic call. Qatar candidates
use `medical_appointment` and `medical_fit`; Saudi and other countries have different
medical stages, so these two voices do not fire for them.

The stage mapping is installed by `AiCalls::InstallStarterRobocallVoicesService`. Stages
are left switched off until an admin turns them on under *Automatic calls*.

## 538 - Upload documents (about 36 s)

**Meaning.** The call is from Descon Engineering Limited, Manpower Services Department.
It asks the candidate to log in to the MPS Connect mobile app and scan and upload
all required documents and the receipt for the medical fee issued by the medical lab. It
warns that mobilization may be delayed if this is not done soon.

**Transcript (Urdu, machine-generated).**

> السلام علیکم یہ کال آپ کو ڈیسکون انجینئرنگ لمیٹڈ مین پاور سروسز ڈیپارٹمنٹ کی جانب سے کی جا رہی ہے۔ آپ سے گزارش ہے کہ ڈیسکون ایم پی ایس کنیکٹ موبائل ایپلیکیشن میں لاگ ان کر کے اپنے تمام مطلوبہ دستاویزات اور میڈیکل لیب کی جانب سے جاری کردہ میڈیکل فیس کی رسید واضح طور پر اسکین کر کے اپلوڈ کر دیں۔ براہ کرم یہ عمل جلد از جلد مکمل کریں، بصورت دیگر آپ کی موبلائزیشن میں تاخیر ہو سکتی ہے۔ منجانب ڈیسکون انجینئرنگ لمیٹڈ مین پاور سروسز ڈیپارٹمنٹ، شکریہ۔

## 537 - Medical report received (about 45 s)

**Meaning.** The medical report has been received from the medical lab. The candidate is
asked to pay the fee as soon as possible using the QuickPay code received on their mobile
phone, through JazzCash, Easypaisa or any online banking app. It warns that mobilization
may be delayed otherwise.

**Transcript (Urdu, machine-generated).**

> السلام علیکم یہ کال آپ کو ڈیسکون انجینئرنگ لمیٹڈ مین پاور سروسز ڈیپارٹمنٹ کی جانب سے کی جا رہی ہے۔ آپ کو اطلاع دی جاتی ہے کہ آپ کی میڈیکل رپورٹ ہمیں میڈیکل لیب سے موصول ہو چکی ہے۔ آپ سے گزارش ہے کہ اپنے موبائل فون پر موصول ہونے والے کوئیک پے کوڈ کے ذریعے اپنی فیس جلد از جلد جمع کروائیں۔ آپ یہ فیس جیز کیش، ایزی پیسہ یا کسی بھی آن لائن بینکنگ ایپلیکیشن کے ذریعے ادا کر سکتے ہیں۔ براہ کرم فیس کی ادائیگی کا عمل جلد از جلد مکمل کریں، بصورت دیگر آپ کی موبلائزیشن میں تاخیر ہو سکتی ہے۔ منجانب ڈیسکون انجینئرنگ لمیٹڈ مین پاور سروسز ڈیپارٹمنٹ، شکریہ۔

**Open point.** This recording promises a payment code sent to the candidate's mobile.
Nothing in the system sends that code yet (payments are still being decided), so either
that must exist before this call goes live, or the recording needs to change.

## 536 - Medical date and center added (about 51 s)

**Meaning.** The QVC medical date, time and center details have been updated in the
MPS Connect mobile app. The candidate should log in, check them carefully and be at
the stated center on the stated date and time. If they fail the QVC medical, they must pay
the fee for repeating it themselves.

**Transcript (Urdu, machine-generated).**

> السلام علیکم جی، یہ کال آپ کو ڈیسکون انجینئرنگ لمیٹڈ مین پاور سروسز ڈیپارٹمنٹ کی جانب سے کی جا رہی ہے۔ آپ کو اطلاع دی جاتی ہے کہ آپ کی کیو سی میڈیکل کی تاریخ اور سینٹر کی تفصیلات ڈیسکون ایم پی ایس کنیکٹ موبائل ایپلیکیشن میں اپڈیٹ کر دی گئی ہیں۔ براہ کرم ڈیسکون ایم پی ایس کنیکٹ موبائل ایپلیکیشن میں لاگ ان کر کے اپنے کیو سی میڈیکل کی تاریخ، وقت اور سینٹر کی تفصیلات اچھی طرح چیک کر لیں اور مقررہ تاریخ اور وقت پر متعلقہ سینٹر میں اپنی حاضری کو یقینی بنائیں۔ یاد رکھیں کہ کیو سی میڈیکل میں ناکامی کی صورت میں دوبارہ میڈیکل کروانے کی فیس آپ کو خود ادا کرنی ہوگی۔ منجانب ڈیسکون انجینئرنگ لمیٹڈ مین پاور سروسز ڈیپارٹمنٹ، شکریہ۔
