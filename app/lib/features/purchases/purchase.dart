import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../widgets/date_range_bar.dart';
import '../auth/auth_controller.dart';

const chickenTypes = {'live': 'Live', 'dressed': 'Dressed', 'cleaned': 'Cleaned'};
const rateUnits = {'per_kg': 'Per KG', 'per_bird': 'Per bird'};

/// Random key sent with create requests so a double-tap cannot save twice.
String newIdempotencyKey() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class Purchase {
  Purchase(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String get refNo => j['ref_no'] as String;
  String get supplierName => j['supplier']['name'] as String;
  int get supplierId => j['supplier']['id'] as int;
  DateTime get date => DateTime.parse(j['purchase_date'] as String);
  String? get time => (j['receiving_time'] as String?)?.substring(0, 5);
  String get chickenType => j['chicken_type'] as String;
  int get birds => j['birds'] as int;
  String get grossWeight => '${j['gross_weight']}';
  String get netWeight => '${j['net_weight']}';
  String get rate => '${j['rate']}';
  String get rateUnit => j['rate_unit'] as String;
  String get amount => '${j['amount']}';
  String get transport => '${j['transport_charges']}';
  String get other => '${j['other_expenses']}';
  String get totalCost => '${j['total_cost']}';
  String? get supplierRef => j['supplier_ref'] as String?;
  String? get notes => j['notes'] as String?;
  bool get cancelled => j['status'] == 'cancelled';
  String? get cancelReason => j['cancel_reason'] as String?;
}

class PurchaseListResult {
  PurchaseListResult(this.items, this.totals);
  final List<Purchase> items;
  final Map<String, dynamic> totals;
}

class PurchaseRepository {
  PurchaseRepository(this._api);
  final ApiClient _api;

  Future<PurchaseListResult> list(DayRange range, {bool includeCancelled = false, String? q}) async {
    final r = await _api.get('/purchases', query: {
      'date_from': range.apiFrom,
      'date_to': range.apiTo,
      'include_cancelled': includeCancelled,
      'q': q,
    });
    return PurchaseListResult(
      (r['items'] as List).map((e) => Purchase(e as Map<String, dynamic>)).toList(),
      r['totals'] as Map<String, dynamic>,
    );
  }

  Future<Purchase> create(Map<String, dynamic> body) async =>
      Purchase(await _api.post('/purchases', body) as Map<String, dynamic>);

  Future<Purchase> cancel(int id, String reason) async =>
      Purchase(await _api.post('/purchases/$id/cancel', {'reason': reason}) as Map<String, dynamic>);
}

final purchaseRepoProvider = Provider((ref) => PurchaseRepository(ref.watch(apiClientProvider)));

typedef PurchaseQuery = ({DayRange range, bool includeCancelled, String q});

final purchaseListProvider = FutureProvider.autoDispose.family<PurchaseListResult, PurchaseQuery>(
  (ref, q) => ref.watch(purchaseRepoProvider).list(q.range, includeCancelled: q.includeCancelled, q: q.q),
);
