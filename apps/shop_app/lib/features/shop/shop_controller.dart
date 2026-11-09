import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_exception.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/offline_first_repository.dart';
import '../../domain/entities/models.dart';

/// يدير محلات المستخدم والمحل النشط.
///
/// **دون اتصال:** تُعرض النسخة المحفوظة محليًا من آخر جلب ناجح، فيعرف
/// التطبيق محله ولا يطلب إنشاء محل جديد.
///
/// **قاعدة مهمة:** المحل النشط المحفوظ على الجهاز هو المرجع الأول. كان
/// التطبيق يأخذ `shops.first` (ترتيب أبجدي) فيبدّل المحل عند كل إقلاع
/// ويعرض بيانات محل آخر — خصوصًا دون اتصال.
class ShopController extends ChangeNotifier {
  ShopController({
    required ApiClient api,
    required OfflineFirstRepository repository,
    Future<void> Function(String shopId)? onSelected,
  })  : _api = api,
        _repository = repository,
        _onSelected = onSelected;

  final ApiClient _api;
  final OfflineFirstRepository _repository;

  /// يُستدعى عند اختيار المستخدم محلًا صريحًا (لحفظ الاختيار على الجهاز).
  final Future<void> Function(String shopId)? _onSelected;

  List<Shop> _shops = const [];
  Shop? _active;
  bool _loading = false;
  bool _offline = false;
  bool _loadFailed = false;
  bool _loaded = false;
  String? _error;

  /// المحل المفضّل (المحفوظ على الجهاز) — يبقى مرجع الاختيار.
  String? _preferredShopId;

  List<Shop> get shops => _shops;
  Shop? get active => _active;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasShop => _active != null;

  /// هل انتهى أول تحميل (نجاحًا أو فشلًا)؟ يميّز التهيئة من «بلا محل».
  bool get loaded => _loaded;

  /// هل المحل معروض من النسخة المحلية (لا اتصال)؟
  bool get offline => _offline;

  /// هل فشل تحميل المحلات دون وجود نسخة محلية؟
  ///
  /// عندها يجب عرض خطأ مع زر إعادة المحاولة — لا شاشة «إعداد المحل»،
  /// لأن الفشل لا يعني أن المستخدم بلا محل.
  bool get loadFailed => _loadFailed;

  String? get preferredShopId => _preferredShopId;

  /// يحمّل المحلات. مرّر [preferredShopId] (المحل المحفوظ) قبل التحميل.
  Future<void> load({String? preferredShopId}) async {
    if (preferredShopId != null && preferredShopId.isNotEmpty) {
      _preferredShopId = preferredShopId;
    }
    _loading = true;
    _error = null;
    _loadFailed = false;
    notifyListeners();
    try {
      // أظهر آخر محل محفوظ فورًا. لا نربط فتح التطبيق باستجابة Render.
      final cached = await _repository.cachedShops();
      if (cached.isNotEmpty) {
        _shops = cached;
        _active = _selectActive(cached);
        _offline = true;
        _loading = false;
        notifyListeners();
        unawaited(_refreshInBackground());
        return;
      }
      await _loadFromRemote();
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// إعادة المحاولة بعد فشل التحميل مع الإبقاء على المحل المفضّل.
  Future<void> retry() => load();

  /// جلب من الخادم مع محاولتين: أول فشل عابر (استيقاظ الخادم مثلًا) لا
  /// يجوز أن يُظهر للمستخدم أنه بلا محل.
  Future<void> _loadFromRemote() async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await _repository.listShops();
        if (!result.failed) {
          _shops = result.shops;
          _active = _shops.isEmpty ? null : _selectActive(_shops);
          _offline = result.fromCache;
          _error = null;
          _loadFailed = false;
          return;
        }
        lastError = 'تعذر تحميل بيانات المحل.';
      } catch (error) {
        lastError = error;
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    _shops = const [];
    _active = null;
    _offline = false;
    _loadFailed = true;
    _error = lastError is ApiException
        ? lastError.message
        : 'تعذر تحميل بيانات المحل. تحقق من الاتصال وأعد المحاولة.';
  }

  /// يختار المحل النشط: المفضّل المحفوظ، ثم الحالي، ثم الأول.
  Shop _selectActive(List<Shop> shops) {
    final preferred = _preferredShopId ?? _active?.id;
    if (preferred != null) {
      for (final shop in shops) {
        if (shop.id == preferred) return shop;
      }
    }
    final active = _active;
    if (active != null) {
      for (final shop in shops) {
        if (shop.id == active.id) return shop;
      }
    }
    return shops.first;
  }

  Future<void> _refreshInBackground() async {
    try {
      final remote = await _repository.refreshShops();
      if (remote.isEmpty) return;
      _shops = remote;
      _active = _selectActive(remote);
      _offline = false;
      _error = null;
      _loadFailed = false;
      notifyListeners();
    } catch (_) {
      // تبقى النسخة المحلية ظاهرة ولا نعرض خطأً أحمر بسبب توقف الخادم.
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
      // احفظه قبل إشعار الواجهة: قد يبدأ AppRoot إعادة تحميل في اللحظة نفسها.
      await _repository.cacheShop(shop);
      _shops = [shop, ..._shops];
      await select(shop);
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

  /// يحدّث بيانات المحل النشط — يعيد null عند النجاح أو رسالة الخطأ.
  Future<String?> update({
    String? name,
    String? currency,
    String? timezone,
  }) async {
    final shop = _active;
    if (shop == null) return 'لا يوجد محل نشط.';
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _api.updateShop(
        shop.id,
        name: name,
        currency: currency,
        timezone: timezone,
      );
      await _repository.cacheShop(updated);
      _shops = _shops
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
      if (_active?.id == updated.id) _active = updated;
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر تحديث بيانات المحل.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// يبدّل المحل النشط ويحفظ الاختيار على الجهاز فورًا.
  Future<void> select(Shop shop) async {
    _active = shop;
    _preferredShopId = shop.id;
    notifyListeners();
    try {
      await _onSelected?.call(shop.id);
    } catch (_) {
      // فشل الحفظ لا يمنع التبديل في الجلسة الحالية.
    }
  }
}
