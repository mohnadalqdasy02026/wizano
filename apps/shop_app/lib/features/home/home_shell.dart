import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/connectivity.dart';
import '../customers/customers_screen.dart';
import '../messages/messages_screen.dart';
import '../home/dashboard_screen.dart';
import '../payments/payments_screen.dart';
import '../profile/profile_screen.dart';
import '../purchases/purchases_screen.dart';
import '../settings/settings_screen.dart';

/// S07 — شريط التنقل الرئيسي: ينتقل بين الأقسام.
/// كشف الحساب (S18) يُفتح من ملف العميل (S11) وليس تبويبًا مستقلًا.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    DashboardScreen(),
    CustomersScreen(),
    PurchasesScreen(),
    PaymentsScreen(),
    MessagesScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<ConnectivityMonitor>().offline;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _tabs),
          Positioned(
            right: 14,
            bottom: 14,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 240),
              offset: offline ? Offset.zero : const Offset(0, 1.5),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: offline ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !offline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: WizanoColors.navy,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .18),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 17,
                          color: Colors.white,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'وضع دون اتصال',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: WizanoColors.blue.withValues(alpha: 0.10))),
            boxShadow: [
              BoxShadow(
                color: WizanoColors.navy.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            children: [
              _AnimatedNavItem(index: 0, currentIndex: _index, icon: Icons.dashboard_rounded, label: 'الرئيسية', onTap: _select),
              _AnimatedNavItem(index: 1, currentIndex: _index, icon: Icons.people_alt_rounded, label: 'العملاء', onTap: _select),
              _AnimatedNavItem(index: 2, currentIndex: _index, icon: Icons.receipt_long_rounded, label: 'المشتريات', onTap: _select),
              _AnimatedNavItem(index: 3, currentIndex: _index, icon: Icons.payments_rounded, label: 'المدفوعات', onTap: _select),
              _AnimatedNavItem(index: 4, currentIndex: _index, icon: Icons.forum_rounded, label: 'الرسائل', onTap: _select),
              _AnimatedNavItem(index: 5, currentIndex: _index, icon: Icons.person_rounded, label: 'الملف', onTap: _select),
              _AnimatedNavItem(index: 6, currentIndex: _index, icon: Icons.settings_rounded, label: 'الإعدادات', onTap: _select),
            ],
          ),
        ),
      ),
    );
  }

  void _select(int index) => setState(() => _index = index);
}

class _AnimatedNavItem extends StatelessWidget {
  const _AnimatedNavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final int currentIndex;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = index == currentIndex;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(20),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          tween: Tween(begin: 0, end: selected ? 1 : 0),
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, -5 * value),
            child: Transform.scale(scale: 1 + (0.12 * value), child: child),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 8, vertical: 5),
                decoration: BoxDecoration(
                  color: selected ? WizanoColors.teal.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: selected
                      ? [BoxShadow(color: WizanoColors.teal.withValues(alpha: 0.24), blurRadius: 12)]
                      : null,
                ),
                child: Icon(icon, size: 22, color: selected ? WizanoColors.navy : WizanoColors.textMuted),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? WizanoColors.navy : WizanoColors.textMuted,
                ),
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


