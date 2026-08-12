# خطوات الإطلاق النهائية — EliteRadIq

## قبل البدء

احتفظ بنسخة من قاعدة البيانات، والسورس، ومفتاح Android، وشهادات Apple في أماكن آمنة منفصلة. لا تستخدم بيانات مرضى حقيقية أثناء الاختبار.

## أولاً: Supabase

1. افتح SQL Editor في مشروع الإنتاج.
2. طبّق الملفات التالية واحداً بعد الآخر وتوقف عند أي خطأ:
   - `20260810_base_schema.sql`
   - `20260811_production_security.sql`
   - `20260812_activation_rate_limit.sql`
   - `20260813_release_hardening.sql`
3. أنشئ مستخدم إدارة عبر Supabase Auth.
4. من بيئة موثوقة، اضبط `app_metadata` لهذا المستخدم إلى `{"role":"admin"}`.
5. سجّل الدخول من شاشة المطور واختبر إنشاء كود عشوائي، مستخدم معلّق، تغيير المدة، الإلغاء، والحذف.
6. تحقق أن مفاتيح `anon` لا تستطيع قراءة الجداول مباشرة.

## ثانياً: Backend

انشر مجلد `backend/` على Render أو خدمة Node.js 20+، واضبط متغيرات `.env.example` في لوحة الخادم. لا تنسخ ملف `.env` إلى التطبيق.

بعد النشر:

```bash
curl -fsS https://eliteradiq-api.onrender.com/health
```

يجب أن يرجع JSON يحتوي `"ok":true`. اختبر أن `/api/chat` دون `Authorization` و`X-Registration-Id` يرجع 401، وأن `/api/activate` يطبق 429 بعد المحاولات المتكررة، ثم اختبر كل endpoint بحساب تفعيل تجريبي. أبقِ حداً إضافياً حسب IP في Render/Cloudflare لأن الحد الموجود داخل عملية Node لا يتشارك حالته بين عدة نسخ خادم.

## ثالثاً: صفحات الويب

انشر الملفات عبر `netlify.toml`، ثم افتح في نافذة خاصة:

- `https://unrivaled-belekoy-e397c4.netlify.app/privacy-policy.html`
- `https://unrivaled-belekoy-e397c4.netlify.app/account-deletion.html`

إذا تغير النطاق، حدّث الروابط في شاشات Flutter وفي نماذج المتاجر قبل البناء.

## رابعاً: Android

1. ثبّت Flutter Stable وAndroid SDK 36 وJDK 17.
2. نفّذ الفحص العام المذكور أدناه.
3. أنشئ مفتاح Upload/Release وفق حساب Google Play واحفظه خارج المشروع.
4. أنشئ `android/key.properties` محلياً:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=YOUR_KEY_ALIAS
storeFile=/absolute/secure/path/upload-keystore.jks
```

5. ابنِ الحزمة:

```bash
flutter build appbundle --release
```

6. ارفع AAB إلى Internal Testing أولاً، ثم اختبر التثبيت والتحديث على أجهزة فعلية.

## خامساً: iOS

1. استخدم macOS مع Flutter وXcode/CocoaPods المدعومة.
2. نفّذ `flutter pub get` ثم افتح `ios/Runner.xcworkspace`.
3. راجع Bundle Identifier وTeam وSigning & Capabilities وأوصاف الأذونات وPrivacy Manifest.
4. ابنِ:

```bash
flutter build ipa --release
```

5. راجع Archive في Xcode Organizer وارفعه إلى TestFlight.
6. اختبر على iPhone فعلي، خصوصاً Keychain والتفعيل والميكروفون والكاميرا والحذف.

## الفحص الإلزامي قبل كل بناء

```bash
flutter clean
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
npm test --prefix backend
```

احتفظ بملف `pubspec.lock` الناتج في مستودع الإصدار، وزد رقم النسخة عند كل رفع.

## سيناريو اختبار قبول مختصر

1. تثبيت نظيف ثم قبول التنبيه التعليمي وفتح سياسة الخصوصية.
2. كود خاطئ متكرر ثم lockout؛ كود صحيح ثم إعادة فتح التطبيق.
3. سؤال نصي، صورة، PDF، صورة مرجعية، توليد رسم تعليمي، وبلاغ سلامة.
4. تسجيل/تشغيل/مشاركة/حذف صوت، إملاء، مكالمة، وHi Ray بعد منح ورفض الأذونات.
5. كاميرا لقطة واحدة ووضع دوري، ثم إرسال التطبيق للخلفية والتأكد من توقف الكاميرا/الميكروفون.
6. إنشاء/فتح/حذف سجل محادثة وتصدير PDF/Word متوافق.
7. قطع الشبكة أثناء الطلب، الضغط على إيقاف، تبديل الغرفة، والعودة بعد الشبكة.
8. حذف الحساب والبيانات ثم التأكد من عدم دخول الواجهة المحمية بالجلسة القديمة.
9. تسجيل إدارة صحيح وخاطئ، إنشاء أكواد/مستخدمين، تغيير المدة والحذف.

أنشئ قبل الإرسال أكواد تفعيل مستقلة للمراجعين في Google Play وApp Store، واختبر كل كود على تثبيت نظيف، ثم اكتب خطوات التفعيل بوضوح في Review Notes. لا تضع حساب الإدارة أو كلمة مروره في ملاحظات المراجعة.

لا تنتقل من TestFlight/Internal Testing إلى الإنتاج قبل نجاح هذه السيناريوهات دون crash أو تسرب بيانات.
