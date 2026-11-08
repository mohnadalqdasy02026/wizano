-- إعادة تعيين كاملة لبيانات الإنتاج (مرة واحدة).
--
-- طلب المالك: بدء قاعدة نظيفة تمامًا (لا مستخدمين ولا محلات ولا عمليات)
-- لإعادة اختبار التطبيق من الصفر. تُنفَّذ مرة واحدة فقط لأن Drizzle يسجّل
-- الترحيل في drizzle.__drizzle_migrations، ولا تُحذف بيانات سجل الترحيل نفسه.
--
-- ملاحظة أمان: TRUNCATE لا يُشغّل trigger منع حذف سجل التدقيق (وهو trigger
-- على UPDATE/DELETE فقط)، لذا تمرّ إعادة التعيين دون تعطيل الحماية الدائمة.
--
-- نتحقق من وجود الجدول قبل اقتطاعه حتى تنجح على قاعدة قديمة لا تحتوي
-- بعض الجداول (مثل customer_messages) بدل أن يفشل النشر بالكامل.

DO $$
DECLARE
  target text;
  existing text[] := '{}';
  targets text[] := ARRAY[
    'objection_replies',
    'objections',
    'financial_adjustments',
    'purchase_returns',
    'payments',
    'purchases',
    'customer_messages',
    'invitations',
    'customer_shop_links',
    'sync_operations',
    'audit_logs',
    'notifications',
    'device_registrations',
    'refresh_tokens',
    'shop_counters',
    'shop_members',
    'customer_user_links',
    'customers',
    'shops',
    'users'
  ];
BEGIN
  FOREACH target IN ARRAY targets LOOP
    IF EXISTS (
      SELECT 1
      FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = target
    ) THEN
      existing := existing || format('%I.%I', 'public', target);
    END IF;
  END LOOP;

  IF array_length(existing, 1) > 0 THEN
    EXECUTE 'TRUNCATE TABLE ' || array_to_string(existing, ', ') || ' RESTART IDENTITY CASCADE';
  END IF;
END $$;
