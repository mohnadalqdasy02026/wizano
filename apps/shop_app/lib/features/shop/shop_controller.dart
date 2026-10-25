import 'package:flutter/foundation.dart';

import '../../core/api_exception.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/offline_first_repository.dart';
import '../../domain/entities/models.dart';

/// يدير محلات المستخدم والمحل النشط.
///
/// **دون اتصال:** تُعرض النسخة المحفوظة محليًا من آخر جلب ناجح، فيعرف
/// التطبيق محله ولا يطلب إنشاء محل جديد.
class ShopController extends ChangeNotifier {
  ShopController({
    required ApiClient api,
    required OfflineFirstRepository repository,
  })  : _api = api,
        _repository = repository;

  final ApiClient _api;
  final OfflineFirstRepository _repository;

  List<Shop> _shops = const [];
  Shop? _active;
  bool _loading = false;
  bool _offline = false;
  String? _error;

  List<Shop> get shops => _shops;
  Shop? get active => _active;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasShop => _active != null;

  /// هل المحل معروض من النسخة المحلية (لا اتصال)؟
  bool get offline => _offline;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.listShops();
      _offline = result.fromCache;
      _shops = result.shops;
      _active = _shops.isNotEmpty ? _shops.first : null;
    } on ApiException catch (e) {
      _error = e.message;
      _shops = const [];
      _active = null;
    } catch (_) {
      _error = 'تعذر تحميل بيانات المحل.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// إنشاء محل وتعيينه نشطًا — يعيد null عند النجاح أو رسالة الخطأ.
  Future<String?> create({
    required String name,
    String? currency,
    String? timezone,
    String? openingDate,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final shop = await _api.createShop(
        name: name,
        currency: currency,
        timezone: timezone,
        openingDate: openingDate,
      );
      _shops = [shop, ..._shops];
      _active = shop;
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر إنشاء المحل.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void select(Shop shop) {
    _active = shop;
    notifyListeners();
  }
}
