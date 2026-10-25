# WIZANO | وزانو — تطبيق صاحب المحل: البنية والشاشات الأساسية (المرحلة 6)

| البند | القيمة |
|---|---|
| رقم الوثيقة | WZ-APP-002 |
| الإصدار | 1.0 |
| المرحلة | المرحلة 6 — لوحة التحكم والشاشات الأساسية |
| المصدر | `apps/shop_app/lib/` |

---

## 1. الهدف

بناء العمود الفقري لتطبيق صاحب المحل: طبقة وصول للبيانات حقيقية (لا وهمية)،
إدارة جلسة، وتنقّل بين الشاشات الأساسية مع حالات الواجهة الموحّدة
(تحميل / فراغ / خطأ) — دون بيانات مالية (تأتي في المراحل 8+).

---

## 2. الشاشات المُنفَّذة

| # | الشاشة | الملف | الحالة |
|---|---|---|---|
| S01 | شاشة البداية (Splash) | `features/auth/splash_screen.dart` | ✅ فحص الجلسة + تحميل المحلات |
| S02 | تسجيل الدخول | `features/auth/login_screen.dart` | ✅ بريد + كلمة مرور |
| S03 | إنشاء حساب | `features/auth/register_screen.dart` | ✅ اسم + بريد + كلمة مرور |
| S04 | إعداد ملف المحل | `features/shop/shop_setup_screen.dart` | ✅ اسم/عملة/منطقة/تاريخ |
| S05 | الملف الشخصي | `features/profile/profile_screen.dart` | ✅ بيانات + خروج |
| S06 | لوحة التحكم | `features/home/dashboard_screen.dart` | ✅ البنية + حالات (البيانات المالية لاحقًا) |
| S07 | شريط التنقل | `features/home/home_shell.dart` | ✅ 3 تبويبات |
| S28 | الإعدادات (جزئي) | `features/settings/settings_screen.dart` | ✅ الحساب/المحل/خروج |

**التوجيه التلقائي** (`app/app_root.dart`): غير معروفة → S01؛ غير مُصادَق → S02؛
مُصادَق بلا محل → S04؛ مُصادَق مع محل → S07/S06.

---

## 3. الطبقات

```
lib/
  core/            api_exception.dart, token_store.dart
  domain/entities/ models.dart (User, AuthTokens, AuthSession, Shop)
  data/remote/     api_client.dart
  data/repositories/auth_repository.dart
  features/
    auth/          splash, login, register, auth_controller
    shop/          shop_setup_screen, shop_controller
    home/          dashboard_screen, home_shell
    profile/       profile_screen
    settings/      settings_screen
  app/             app_root, theme, widgets
```

- **ApiClient**: يضيف `Bearer` تلقائيًا، يوحد الأخطاء إلى `ApiException`
  برسالة عربية، ويجدد الرمز مرة واحدة عند 401 (تدوير) ثم يعيد المحاولة.
- **TokenStore**: واجهة مجرّدة + تنفيذ `InMemoryTokenStore`؛ قابل للاستبدال
  بتنفيذ آمن على القرص (flutter_secure_storage) دون تغيير المستهلكين.
- **AuthController / ShopController**: `ChangeNotifier` عبر Provider.

---

## 4. حالات الواجهة الموحّدة

`widgets.dart` يوفّر `LoadingState` / `EmptyState` / `ErrorState` مع زر إعادة
المحاولة — مطابقة لقسم 4 في `02-screens-map.md`.

---

## 5. التغطية الاختبارية (14 اختبارًا)

- واجهة API: الصحة (4)، المصادقة (4: دخول/تسجيل/خطأ عربي/تجديد عند 401)، المحلات (2).
- واجهة UI: S01 أثناء الفحص، S02 بلا جلسة، S02 خطأ دخول عربي، الهبوط إلى S04 (4).

---

## 6. خارج نطاق هذه المرحلة

- البيانات المالية في لوحة التحكم (المراحل 8+).
- تنزيل نموذج الصوت واللغة في S28 (المرحلة 12).
- أقسام العملاء/المشتريات/المدفوعات/الكشف في S07 (المراحل 7-10).
- التخزين الآمن على القرص (الخطة: flutter_secure_storage — قرار بيئي).
