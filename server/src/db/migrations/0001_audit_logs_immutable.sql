-- ترحيل مخصص (لا يولّده drizzle-kit): قواعد سلامة لا يعبّر عنها المخطط.
-- يُطبَّق بعد الترحيل 0000 ويُسجَّل في meta/_journal.json بنفس الصيغة.

CREATE SCHEMA IF NOT EXISTS app_logic;

-- منع تعديل أو حذف سجل التدقيق نهائيًا (متطلب الأمان §10.6 + D-10).
CREATE OR REPLACE FUNCTION app_logic.prevent_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'سجل التدقيق غير قابل للتعديل أو الحذف';
END;
$$;

DROP TRIGGER IF EXISTS audit_logs_immutable ON public.audit_logs;

CREATE TRIGGER audit_logs_immutable
BEFORE UPDATE OR DELETE ON public.audit_logs
FOR EACH ROW
EXECUTE FUNCTION app_logic.prevent_audit_log_mutation();
