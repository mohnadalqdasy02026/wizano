import 'package:flutter/material.dart';

import 'theme.dart';

/// حقل إدخال موحّد بتهيئة RTL وعنوان عربي.
class WizanoField extends StatelessWidget {
  const WizanoField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscure = false,
    this.textInputAction,
    this.validator,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD0D7E2)),
          ),
        ),
      ),
    );
  }
}

/// بطاقة خطأ موحّدة مع زر إعادة المحاولة.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: WizanoColors.error, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WizanoColors.textDark, fontSize: 15),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// حالة فراغ موحّدة: رسالة + إجراء مباشر اختياري.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: WizanoColors.textMuted, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WizanoColors.textMuted, fontSize: 15),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// تنبيه «لا يوجد اتصال» — يُعرض في نماذج الحفظ قبل إتمام العملية.
class OfflineNotice extends StatelessWidget {
  const OfflineNotice({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WizanoColors.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: WizanoColors.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ??
                  'لا يوجد اتصال بالخادم — ستُحفظ العملية محليًا وتُرسل لاحقًا.',
              style: const TextStyle(
                color: WizanoColors.navy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط تنبيه ثابت أعلى المحتوى: لا يوجد اتصال بالخادم.
class OfflineStrip extends StatelessWidget {
  const OfflineStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: WizanoColors.gold,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: WizanoColors.navy),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'لا يوجد اتصال بالخادم — العمليات تُحفظ محليًا وتُرسل لاحقًا.',
              style: TextStyle(
                color: WizanoColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// واجهة انقطاع كاملة عندما لا توجد أي بيانات محلية لعرضها بعد.
class OfflineEmptyState extends StatelessWidget {
  const OfflineEmptyState({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/offline_sync.png', height: 155),
              const SizedBox(height: 16),
              const Text(
                'لا يوجد اتصال بالإنترنت',
                style: TextStyle(
                  color: WizanoColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'يمكنك متابعة العمل بالبيانات المحفوظة، وستتم المزامنة تلقائيًا عند عودة الشبكة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: WizanoColors.textMuted, height: 1.5),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.wifi_find_rounded),
                  label: const Text('محاولة الاتصال'),
                ),
              ],
            ],
          ),
        ),
      );
}

/// حالة تحميل موحّدة.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message = 'جارٍ التحميل...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: WizanoColors.textMuted)),
        ],
      ),
    );
  }
}

/// شعار المنتج النصي.
class WizanoLogo extends StatelessWidget {
  const WizanoLogo({super.key, this.tagline = true});

  final bool tagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/app_icon.png',
          height: 94,
          filterQuality: FilterQuality.high,
        ),
        const SizedBox(height: 6),
        const Text(
          'WIZANO | وزانو',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: WizanoColors.navyBright,
          ),
        ),
        if (tagline) ...[
          const SizedBox(height: 8),
          const Text(
            '«حسابك واضح، وحقك محفوظ.»',
            style: TextStyle(
              fontSize: 17,
              color: WizanoColors.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
