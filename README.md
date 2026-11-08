# WIZANO | وزانو

«حسابك واضح، وحقك محفوظ.»

نظام إدارة الديون والمشتريات والمدفوعات للمحلات التجارية — **قيد التطوير بمنهجية المراحل العشرين**.

## بنية المستودع

```
wizano/
├── apps/
│   └── shop_app/        # تطبيق صاحب المحل (Flutter — Android)
├── server/              # الخادم المركزي (Node.js + Fastify + TypeScript + PostgreSQL)
└── docs/                # وثائق التحليل والتصميم (مرجع المشروع)
```

> تطبيق العميل يُنشأ لاحقًا (المرحلة 17) داخل `apps/customer_app/`.

## المتطلبات الأساسية

| الأداة | الإصدار المفحوص |
|---|---|
| Flutter / Dart | 3.35.3 / 3.9.2 |
| Node.js / npm | 24.15 / 11.12 |
| PostgreSQL | 16.15 |

**ملاحظة Windows:** استدعِ npm عبر `npm.cmd` (أو `npm run` من داخل `server/` بطرفية عادية) لأن `npm.ps1` مرفوض بسياسة التنفيذ.

## تشغيل الخادم

```powershell
cd server
npm.cmd install          # أول مرة فقط
npm.cmd run dev          # تشغيل التطوير على http://localhost:4000
```

> **تنبيه:** إذا كان المنفذ 4000 محجوزًا (مثلاً خادم مشروع آخر)، شغّل وفّزانو على منفذ آخر:
> `$env:API_PORT="4100"; npm.cmd run dev`

فحص سريع (من طرفية أخرى):

```powershell
Invoke-RestMethod http://localhost:4000/api/v1/health
```

المتغيرات: انسخ `server/.env.example` إلى `server/.env` وعدّل القيم. ملف `.env` الحقيقي غير مرفوع في المستودع.
`JWT_ACCESS_SECRET` مطلوب (32 حرفًا على الأقل) ابتداءً من المرحلة 4.

### مسارات المصادقة (المرحلة 4)

| المسار | الوصف |
|---|---|
| `POST /api/v1/auth/register` | تسجيل مستخدم جديد |
| `POST /api/v1/auth/login` | تسجيل الدخول |
| `POST /api/v1/auth/refresh` | تدوير رمز التجديد |
| `POST /api/v1/auth/logout` | إبطال رمز التجديد |
| `GET /api/v1/me` | المستخدم الحالي (يتطلب `Authorization: Bearer <access>`) |

### مسارات المحلات (المرحلة 5)

| المسار | الوصف |
|---|---|
| `POST /api/v1/shops` | إنشاء محل (يصبح المُنشئ مالكًا) |
| `GET /api/v1/shops` | محلات المستخدم |
| `GET /api/v1/shops/:shopId` | تفاصيل محل (لعضو) |
| `PATCH /api/v1/shops/:shopId` | تعديل محل (للمالك فقط) |

### مسارات العملاء (المرحلة 7)

| المسار | الوصف |
|---|---|
| `GET /api/v1/shops/:shopId/customers?search=` | قائمة عملاء المحل + بحث |
| `POST /api/v1/shops/:shopId/customers` | إنشاء عميل وربطه بالمحل |
| `GET /api/v1/shops/:shopId/customers/:customerId` | تفاصيل عميل |
| `PATCH /api/v1/shops/:shopId/customers/:customerId` | تعديل عميل |
| `DELETE /api/v1/shops/:shopId/customers/:customerId` | أرشفة عميل |
| `POST /api/v1/shops/:shopId/customers/:customerId/invitations` | رمز دعوة لربط العميل |

### قواعد البيانات (بيئة التطوير المحلية)

| القاعدة | الاستخدام |
|---|---|
| `wizano_dev` | التطوير |
| `wizano_test` | الاختبارات الآلية |

المستخدم: `wizano_app` (بدون صلاحيات superuser). أوامر شائعة:

```powershell
cd server
npm.cmd run typecheck     # فحص الأنواع
npm.cmd test              # الاختبارات
npm.cmd run db:generate   # توليد ترحيلات (تبدأ من المرحلة 3)
npm.cmd run db:migrate    # تنفيذ الترحيلات
```

## تشغيل تطبيق صاحب المحل

```powershell
cd apps\shop_app
flutter pub get
flutter run               # على محاكي Android أو جهاز متصل
```

عنوان الخادم الافتراضي المدمج في التطبيق: `https://wizano-api.onrender.com` (خادم الإنتاج المنشور على Render).

> **الربط يتم وقت البناء، لا وقت التثبيت.** ملف APK لا يسأل عن عنوان الخادم عند تثبيته؛ العنوان يُثبَّت داخله وقت `flutter build`. ولتوجيهه إلى خادم آخر مرّر `API_BASE_URL`:
>
> ```powershell
> flutter build apk --release --dart-define=API_BASE_URL=https://wizano-api.onrender.com
> ```

للتطوير المحلي على محاكي Android: `http://10.0.2.2:4000` (يشير إلى مضيف الجهاز)، وعلى **جهاز حقيقي** على نفس الشبكة:

```powershell
flutter run --dart-define=API_BASE_URL=http://<IP-الجهاز-الموضيف>:4000
```

اختبارات وفحص:

```powershell
flutter analyze
flutter test
```

## تشغيل تطبيق العميل

بعد أن ينشئ صاحب المحل رمز دعوة للعميل، يسجّل العميل الدخول ويضع الرمز في حقل
«رمز الدعوة» عند أول دخول لربط حسابه. يجب تمرير عنوان HTTPS للخادم في الإصدارات
النهائية:

```powershell
cd apps\customer_app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://api.example.com
```

لتفعيل الربط الذاتي وكشف الحساب الشخصي، نفّذ الترحيلات قبل تشغيل الخادم:

```powershell
cd server
npm.cmd run db:migrate
```

### متطلبات الإصدار النهائي

- عيّن `NODE_ENV=production` و`CORS_ORIGINS` بقائمة الأصول المسموح بها فقط.
- لا تضبط `TRUST_PROXY=true` إلا خلف reverse proxy موثوق.
- أنشئ `android/key.properties` لكل من `apps/shop_app` و`apps/customer_app` بمفاتيح
  `storeFile` و`storePassword` و`keyAlias` و`keyPassword`. الملف ومفاتيح التوقيع
  مستثناة من Git، ولا يُبنى الإصدار النهائي بمفتاح debug.

## النشر على Render

يوجد ملف [`render.yaml`](render.yaml) جاهز لإنشاء API وقاعدة PostgreSQL.
بعد رفع المستودع إلى GitHub، من لوحة Render اختر **New → Blueprint** ثم اختر
المستودع. أدخل قيمة `CORS_ORIGINS` المطلوبة أثناء الإنشاء (مثال:
`https://app.example.com`). يُولِّد Render سر JWT ويربط قاعدة البيانات تلقائيًا.

> قاعدة Render المجانية مناسبة للتجربة فقط: تنتهي بعد 30 يومًا ولا توفر نسخًا
> احتياطية. لا تستخدمها لبيانات ديون حقيقية دون خطة مدفوعة ونسخ احتياطي.

### الموقع التعريفي على نفس الخادم

جذر الخادم `https://wizano-api.onrender.com/` يعرض صفحة هوية وزانو مع لقطات
التطبيقين. الملفات الثابتة في `server/public/` وتُخدَم مباشرة عبر Node `fs`
(بدون حزم إضافية)، والأصول تحت `/assets/`:

```
server/public/index.html          صفحة الهبوط (عربية RTL)
server/public/assets/styles.css   التصميم
server/public/assets/app.js       تبويبات المعرض، العرض المكبّر، حركة الظهور
server/public/assets/brand/       الشعار وصور الهوية وog-cover
server/public/assets/shots/       لقطات التطبيقات
server/public/robots.txt          قواعد الفهرسة
server/public/manifest.webmanifest
server/public/sitemap.xml
```

عند تحديث أي لقطة أو تعديل الصفحة، أعد تشغيل `npm run build` داخل `server/`
ثم أعد النشر. لا يحتاج الخادم إلى إعادة بناء لالتقاط تغييرات `public/`
لأنها تُقرأ من القرص وقت الطلب.

### إبقاء خدمة Render مستيقظة

خطة Render المجانية تُنيم خدمة الويب بعد ~15 دقيقة بلا طلبات خارجية. يرسل
الخادم تلقائيًا نبضة (self-ping) إلى `https://<خدمتك>.onrender.com/api/v1/health`
كل 10 دقائق عندما يكون المتغير `RENDER_EXTERNAL_URL` موجودًا (يضيفه Render
تلقائيًا). لا حاجة لإعداد إضافي، والنبضة تُعطَّل تلقائيًا محليًا.

> النبضة تُبقي الخدمة يقظة لكنها تستهلك ساعات التشغيل الشهرية. خطة Free
> تمنح 750 ساعة/شهر، والتشغيل المتواصل يستهلك نحو 730 ساعة، فاحسب حسابك
> إن أضفت خدمات أخرى. لمراقبة أدق من خارج Render استخدم مراقبًا مجانيًا
> (مثل UptimeRobot) يستهدف نفس مسار `/api/v1/health` كل 5–10 دقائق.

## حالة المراحل

| المرحلة | الحالة |
|---|---|
| 1 — تحليل المشروع وتثبيت المتطلبات | ✅ معتمدة |
| 2 — هيكل المشروع وبيئة التطوير | ✅ معتمدة (APK release/arm64) |
| 3 — تصميم قاعدة البيانات المركزية | ✅ معتمدة (18 جدولًا) |
| 4 — المصادقة والصلاحيات | ✅ معتمدة |
| 5 — المحلات والانتماء | ✅ معتمدة |
| 6 — لوحة التحكم والشاشات الأساسية | ✅ معتمدة |
| 7 — العملاء وربط العميل بالمحل | **منجزة — بانتظار المراجعة** |
| 8 إلى 20 | لم تبدأ |

## الوثائق

الفهرس الكامل في [`docs/README.md`](docs/README.md).

## تنبيهات بيئة التطوير

- `android:usesCleartextTraffic="true"` مفعّل **للتطوير فقط**؛ الإنتاج يستلزم HTTPS (المرحلة 20).
- لا تُرفع ملفات `.env` أو الأسرار إلى المستودع أبدًا.
- بيانات اتصال قاعدة البيانات المحلية موجودة في `server/.env` (غير مرفوع).
