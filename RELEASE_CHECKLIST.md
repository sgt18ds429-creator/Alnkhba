# قائمة إطلاق EliteRadIq

ضع علامة على كل بند في بيئة الإنتاج، وليس على نسخة تجريبية.

## 1. قاعدة البيانات

- [ ] أخذ نسخة احتياطية من مشروع Supabase الحالي.
- [ ] تطبيق `20260810_base_schema.sql`.
- [ ] تطبيق `20260811_production_security.sql`.
- [ ] تطبيق `20260812_activation_rate_limit.sql`.
- [ ] تطبيق `20260813_release_hardening.sql`.
- [ ] التأكد من تفعيل RLS ومن عدم وجود صلاحية جداول مباشرة لـ `anon` أو `authenticated`.
- [ ] إنشاء حساب إداري وإضافة `{"role":"admin"}` إلى `app_metadata` من بيئة موثوقة.
- [ ] اختبار إنشاء كود من 12 محرفاً أو أكثر، تفعيله مرة واحدة، انتهاء المدة، تدوير الرمز، والحذف.

## 2. الخادم

- [ ] نشر `backend/` باستخدام Node.js 20 أو أحدث.
- [ ] ضبط `SUPABASE_URL` و`SUPABASE_SERVICE_ROLE_KEY` و`GEMINI_API_KEY` و`GOOGLE_TTS_API_KEY` على الخادم فقط.
- [ ] تقييد مفاتيح Google للخدمات والبيئة المطلوبة.
- [ ] فحص `GET https://eliteradiq-api.onrender.com/health`.
- [ ] التأكد من رفض `/api/*` دون رمز تفعيل صحيح.
- [ ] اختبار chat/image/transcribe/tts/report بحساب مفعّل.
- [ ] التحقق من حد `/api/activate` حسب عنوان المصدر، وإضافة حد منصة/WAF أمامه؛ معرّف التثبيت وحده لا يمنع المهاجم من تغييره.

## 3. الخصوصية والحذف

- [ ] نشر `privacy-policy.html` و`account-deletion.html` عبر HTTPS.
- [ ] فتح الرابطين من جهاز غير مسجل الدخول والتأكد من ظهورهما.
- [ ] التأكد أن بريد الدعم ورقم WhatsApp ملك للناشر ويمكن متابعتهما.
- [ ] اختبار «حذف الحساب والبيانات» من التطبيق والتأكد من حذف الخادم والمحلي.
- [ ] تعبئة النماذج حسب `docs/STORE_PRIVACY_DECLARATIONS_AR.md` وبما يطابق الإنتاج الفعلي.

## 4. فحص Flutter

```bash
flutter clean
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

- [ ] لا أخطاء تحليل أو اختبارات.
- [ ] مراجعة `flutter pub outdated` وتقييم التحديثات دون ترقية عمياء قبل الإطلاق.
- [ ] مراجعة `pubspec.lock` الناتج وإيداعه في المستودع للإصدارات القابلة للتكرار.

## 5. Android

- [ ] تثبيت Android SDK 36 وقبول الرخص واستخدام JDK 17.
- [ ] إنشاء keystore إنتاجي محفوظ خارج المشروع و`android/key.properties` محلي.
- [ ] التأكد من تطابق `applicationId` مع سجل Google Play: `com.appnukba.appnukba`، أو تغييره قبل أول نشر فقط.
- [ ] تنفيذ `flutter build appbundle --release`.
- [ ] اختبار الـAAB عبر مسار Internal Testing، مع Android 13 و14 و15 و16 وجهاز ضعيف الشبكة.
- [ ] اختبار تثبيت/تحديث النسخة الموقعة وعدم فقدان جلسة التفعيل بلا سبب.

## 6. iOS

- [ ] استخدام macOS ونسخة Xcode المدعومة وإعداد Team وBundle ID والشهادات وProvisioning.
- [ ] فتح `ios/Runner.xcworkspace` لا `Runner.xcodeproj`.
- [ ] تشغيل `flutter build ipa --release` ثم التحقق من Archive في Xcode Organizer.
- [ ] اختبار iPhone فعلي: Keychain، كاميرا، صور، ميكروفون، Speech Recognition، ملفات، حذف الحساب، RTL، وخلفية التطبيق.
- [ ] رفع TestFlight أولاً ومراجعة سجل الأعطال قبل App Review.

## 7. المتجران

- [ ] زيادة `version` في `pubspec.yaml` لكل إصدار جديد.
- [ ] إعداد وصف ولقطات شاشة وأيقونة وبيانات دعم صحيحة.
- [ ] وصف التطبيق كأداة تعليمية لا كجهاز طبي أو خدمة تشخيص.
- [ ] إدخال رابط الخصوصية والحذف، وإكمال Data Safety وApp Privacy وإقرار تطبيق الصحة ومحتوى الذكاء الاصطناعي.
- [ ] إنشاء أكواد تفعيل منفصلة صالحة للمراجعين، وتجربتها على تثبيت نظيف، وكتابتها مع خطوات الدخول في Review Notes؛ لا ترسل حساب الإدارة أو كلمته السرية.
- [ ] توفير آلية بلاغ داخل التطبيق واختبار وصول البلاغ إلى جدول `ai_safety_reports`.
- [ ] عدم رفع أي `.jks` أو `key.properties` أو `service_role` أو مفتاح Google أو شهادة خاصة.
