# مساعد نخبة الأشعة — EliteRadIq

تطبيق Flutter عربي تعليمي لطلاب وتقنيي الأشعة والسونار. يتضمن محادثة بالذكاء الاصطناعي، تحليل صور وملفات PDF بصورة تعليمية، غرفاً تخصصية، رؤية بالكاميرا عند الطلب، مساعداً صوتياً، تسجيلات، تصدير PDF/Word متوافق، إدارة تفعيل، بلاغات سلامة، وحذف الحساب والبيانات.

> التطبيق تعليمي فقط. مخرجاته ليست تشخيصاً، تقرير أشعة معتمداً، أو بديلاً عن الطبيب وبروتوكول المؤسسة.

## ما تم تحصينه في الإصدار 1.1.3+6

- واجهة عربية RTL داكنة بتصميم Material 3 وهوية وأيقونات إطلاق جديدة.
- إبقاء مفاتيح Gemini وGoogle TTS وSupabase `service_role` على الخادم فقط.
- تفعيل V2 عبر بوابة محدودة المحاولات، برمز جلسة عشوائي محفوظ في Keychain/Keystore ومتحقق منه قبل كل طلب ذكاء اصطناعي.
- صلاحيات إدارة عبر Supabase Auth ودور `app_metadata.role=admin`، مع RLS ومنع الوصول المباشر إلى جداول التفعيل.
- حدود أحجام، مهلات، إعادة محاولات محدودة، معالجة أخطاء، إلغاء آمن للطلبات، وتسلسل حفظ المحادثات.
- عدم تشغيل الكاميرا أو الميكروفون تلقائياً؛ الميزات الصوتية والمرئية تبدأ بفعل واضح من المستخدم.
- حذف التفعيل من الخادم ومسح المحادثات والتسجيلات المحلية من داخل التطبيق.
- سياسة خصوصية، صفحة طلب حذف، Privacy Manifest لـ iOS، وتعطيل النسخ الاحتياطي لبيانات التطبيق الحساسة على Android.
- Android `compileSdk/targetSdk 36`، Java 17، AGP 8.9.2، وGradle 8.11.1.

## بنية المشروع

- `lib/`: تطبيق Flutter.
- `backend/`: خادم Node.js 20 الوسيط للذكاء الاصطناعي والصوت والبلاغات.
- `supabase/migrations/`: مخطط قاعدة البيانات ووظائف التفعيل والإدارة الآمنة.
- `privacy-policy.html` و`account-deletion.html`: صفحات الخصوصية والحذف الجاهزة للنشر.
- `docs/FINAL_RELEASE_STEPS_AR.md`: خطوات الإطلاق النهائية بالترتيب.
- `docs/STORE_PRIVACY_DECLARATIONS_AR.md`: دليل تعبئة نماذج خصوصية Google Play وApp Store.

## تشغيل Flutter محلياً

يتطلب Flutter Stable حديثاً يحتوي Dart 3.9 أو أحدث، Android Studio/JDK 17، وXcode على macOS لبناء iOS.

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run
```

ملف `pubspec.lock` غير مرفق لأنه يجب توليده من بيئة Flutter الفعلية عبر `flutter pub get`. الأمر نفسه يعيد توليد ملفات تسجيل الإضافات الأصلية لكل منصة.

## ترتيب تجهيز الإنتاج

1. طبّق ملفات `supabase/migrations/` الأربعة حسب الاسم، من `20260810` إلى `20260813`.
2. أنشئ حساب الإدارة في Supabase Auth واجعل `app_metadata.role` مساوياً `admin`.
3. انشر `backend/` واضبط متغيرات `.env.example` داخل بيئة الخادم فقط.
4. انشر صفحتي الخصوصية والحذف عبر إعداد `netlify.toml` وتحقق من روابط HTTPS.
5. شغّل الفحص والاختبارات والبناء الموقّع على جهاز تطوير حقيقي.
6. اختبر نسخة Release على هاتف Android وiPhone فعليين، ثم أكمل نماذج المتاجر.

التفاصيل والأوامر الدقيقة موجودة في `RELEASE_CHECKLIST.md` و`docs/FINAL_RELEASE_STEPS_AR.md`.

## عناوين الإنتاج المضبوطة في المشروع

- API: `https://eliteradiq-api.onrender.com`
- الخصوصية: `https://unrivaled-belekoy-e397c4.netlify.app/privacy-policy.html`
- حذف الحساب: `https://unrivaled-belekoy-e397c4.netlify.app/account-deletion.html`

هذه العناوين يجب نشرها واختبارها فعلياً قبل تقديم التطبيق للمتاجر؛ وجودها في السورس لا يعني أن الخدمة منشورة أو متاحة.

## التوقيع

لا تتضمن الحزمة مفاتيح توقيع أو شهادات أو كلمات مرور. أنشئ `android/key.properties` وملف keystore محلياً، واضبط Team/Certificates/Provisioning في Xcode. لا ترفع هذه الملفات إلى Git ولا ترسلها داخل ZIP.
