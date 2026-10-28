import 'package:flutter/foundation.dart';

import '../../core/api_exception.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/offline_first_repository.dart';
import '../../domain/entities/models.dart';

/// يدير عملاء المحل النشط: التحميل، البحث، الإضافة، التعديل، الأرشفة، والدعوة.
///
/// **دون اتصال:** تُعرض النسخة المحفوظة محليًا من آخر جلب ناجح (ليختار صاحب
/// المحل عميلًا ويسجّل مشتريات)، أما الإضافة والتعديل فتحتاج اتصالًا وتُخبر
/// المستخدم بذلك بوضوح.
class CustomerController extends ChangeNotifier {
  CustomerController({
    required ApiClient api,
    required OfflineFirstRepository repository,
  })  : _api = api,
        _repository = repository;

  final ApiClient _api;
  final OfflineFirstRepository _repository;

  List<Customer> _customers = const [];
  bool _loading = false;
  bool _offline = false;
  String? _error;
  String? _shopId;

  List<Customer> get customers => _customers;
  bool get loading => _loading;
  String? get error => _error;

  /// هل القائمة معروضة من النسخة المحلية (لا اتصال)؟
  bool get offline => _offline;

  void setShop(String? shopId) {
    if (_shopId == shopId) return;
    _shopId = shopId;
    _customers = const [];
    _error = null;
    _offline = false;
    notifyListeners();
  }

  Future<void> load({String? search}) async {
    if (_shopId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.listCustomers(_shopId!, search: search);
      _offline = result.fromCache;
      // النسخة المحلية تُصفَّى على الجهاز؛ نتيجة الخادم مُصفّاة أصلًا.
      _customers = result.fromCache
          ? _filter(result.customers, search)
          : result.customers;
      if (result.fromCache && _customers.isEmpty) {
        _error = 'تعذر الوصول إلى الخادم ولا توجد نسخة محفوظة من العملاء.';
      }
    } on ApiException catch (e) {
      _error = e.message;
      _customers = const [];
    } catch (_) {
      _error = 'تعذر تحميل قائمة العملاء.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// تصفية محلية بالاسم أو الهاتف (تعمل دون اتصال).
  List<Customer> _filter(List<Customer> items, String? search) {
    final query = (search ?? '').trim().toLowerCase();
    if (query.isEmpty) return items;
    return items
        .where(
          (c) =>
              c.displayName.toLowerCase().contains(query) ||
              (c.phone ?? '').toLowerCase().contains(query),
        )
        .toList();
  }

  /// إضافة عميل — تعيد null عند النجاح أو رسالة الخطأ.
  Future<String?> add({
    required String displayName,
    String? phone,
    String? notes,
  }) async {
    if (_shopId == null) return 'لا يوجد محل نشط.';
    try {
      final outcome = await _repository.createCustomer(
        shopId: _shopId!,
        displayName: displayName,
        phone: phone,
        notes: notes,
      );
      final created = outcome.value;
      if (created == null) return outcome.error ?? 'تعذر إضافة العميل.';
      _customers = [..._customers, created]
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر إضافة العميل.';
    }
  }

  /// تعديل عميل — تعيد null عند النجاح أو رسالة الخطأ.
  Future<String?> edit(
    String customerId, {
    required String displayName,
    String? phone,
    String? notes,
  }) async {
    if (_shopId == null) return 'لا يوجد محل نشط.';
    try {
      final updated = await _api.updateCustomer(
        _shopId!,
        customerId,
        displayName: displayName,
        phone: phone,
        notes: notes,
      );
      _customers = _customers
          .map((c) => c.id == customerId ? updated : c)
          .toList(growable: false);
      await _repository.cacheCustomer(_shopId!, updated);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر تعديل العميل.';
    }
  }

  /// أرشفة عميل — تعيد null عند النجاح أو رسالة الخطأ.
  Future<String?> archive(String customerId) async {
    if (_shopId == null) return 'لا يوجد محل نشط.';
    try {
      await _api.archiveCustomer(_shopId!, customerId);
      _customers =
          _customers.where((c) => c.id != customerId).toList(growable: false);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر أرشفة العميل.';
    }
  }

  /// إنشاء رمز دعوة — يعيد الرمز أو null عند الخطأ.
  Future<Invitation?> invite(String customerId) async {
    if (_shopId == null) return null;
    try {
      return await _api.createInvitation(_shopId!, customerId);
    } catch (_) {
      return null;
    }
  }
}
