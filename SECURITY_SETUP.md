# إعداد الأمان للإنتاج

## نموذج الثقة

- تطبيق Flutter عميل عام ولا يُعد مكاناً سرياً.
- مفتاح Supabase `anon`/publishable قابل للظهور في التطبيق، لذلك الحماية الحقيقية هي RLS وRPCs المحدودة.
- `SUPABASE_SERVICE_ROLE_KEY` و`GEMINI_API_KEY` و`GOOGLE_TTS_API_KEY` أسرار خادم ولا تدخل Flutter أو Git أو سجلات البناء.
- Backend يتحقق من رمز تفعيل V2 قبل صرف أي حصة ذكاء اصطناعي.

## Supabase

طبّق كل migrations بالترتيب. تطبيق الهاتف يستدعي مباشرةً فقط:

- `get_my_registration_v2`
- `deactivate_registration_v2`
- RPCs الإدارة بعد Supabase Auth ودور `admin`

يستدعي Backend دالة `activate_registration_v2` بمفتاح `service_role` بعد تطبيق حد المحاولات حسب عنوان المصدر. لا تمنح `anon` أو `authenticated` تنفيذها أو صلاحية مباشرة على `allowed_codes` أو `registered_users` أو `activation_attempts` أو `ai_safety_reports`. لا تمنح `verify_activation_token` إلا لـ `service_role`.

أنشئ أكواداً عشوائية بطول 12 محرفاً على الأقل، وحدد مدة وعدد استخدامات مناسبين. أبقِ rate limiting على Render/Cloudflare أمام `/api/activate` كطبقة إضافية؛ الحد داخل العملية لا يتشارك حالته بين عدة نسخ خادم.

## Backend

- HTTPS فقط، مع مهلات وحدود حجم وrate limiting على البوابة.
- لا تسجل prompt المستخدم أو الصور أو الصوت أو الرموز إلا عند ضرورة معلنة ومقيدة.
- قيّد مفاتيح Google للخدمات المطلوبة، ودوّرها عند الاشتباه بالتسرب.
- اجعل CORS فارغاً لتطبيقات الهاتف، أو حدد أصول HTTPS الدقيقة فقط إذا نُشر عميل Web.
- راقب أخطاء 401/403/413/429/5xx دون تسجيل أسرار أو محتوى صحي.

## الهاتف والتوقيع

- رمز التفعيل محفوظ في Secure Storage، والمحادثات العادية في تخزين محلي؛ لا تحفظ بيانات مرضى تعريفية.
- Android backup وcleartext traffic معطلان.
- لا تشارك keystore أو كلمات مروره أو شهادات Apple أو ملفات provisioning.
- اختبر النسخة الموقعة على أجهزة حقيقية؛ نجاح Debug لا يثبت نجاح Release.

## حادث أمني

عند تسرب سر: ألغِه من المزود، أنشئ سراً جديداً، حدّث الخادم، راجع السجلات، وأصدر نسخة تطبيق فقط إذا تغير عقد العميل. عند تسرب keystore أو شهادة توقيع اتبع إجراءات الاسترداد الرسمية للمتجر فوراً.
