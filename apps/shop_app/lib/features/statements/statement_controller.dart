import 'package:flutter/foundation.dart';

import '../../core/api_exception.dart';
import '../../data/remote/api_client.dart';
import '../../domain/entities/models.dart';

/// يدير كشف حساب عميل واحد: التحميل مع تصفية النوع والمدى الزمني.
class StatementController extends ChangeNotifier {
  StatementController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  CustomerStatement? _statement;
  bool _loading = false;
  String? _error;

  CustomerStatement? get statement => _statement;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load(
    String shopId,
    String customerId, {
    String? type,
    String? from,
    String? to,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _statement = await _api.getStatement(
        shopId,
        customerId,
        type: type,
        from: from,
        to: to,
      );
    } on ApiException catch (e) {
      _error = e.message;
      _statement = null;
    } catch (_) {
      _error = 'تعذر تحميل كشف الحساب.';
      _statement = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
