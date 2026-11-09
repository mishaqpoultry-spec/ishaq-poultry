import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../widgets/date_range_bar.dart';
import '../auth/auth_controller.dart';

/// Birds and KG are always a pair, never mixed into one number.
class BirdsKg {
  BirdsKg(this.birds, this.weight);
  final int birds;
  final String weight;
  factory BirdsKg.fromJson(Map<String, dynamic> j) => BirdsKg(j['birds'] as int, '${j['weight']}');
}

class StockTypeSummary {
  StockTypeSummary(this.j);
  final Map<String, dynamic> j;
  BirdsKg _g(String k) => BirdsKg.fromJson(j[k] as Map<String, dynamic>);
  BirdsKg get opening => _g('opening');
  BirdsKg get received => _g('received');
  BirdsKg get supplied => _g('supplied');
  BirdsKg get customerReturns => _g('customer_returns');
  BirdsKg get supplierReturns => _g('supplier_returns');
  BirdsKg get losses => _g('losses');
  BirdsKg get processingOut => _g('processing_out');
  BirdsKg get processingIn => _g('processing_in');
  BirdsKg get closing => _g('closing');

  bool get isEmpty =>
      [opening, received, supplied, customerReturns, supplierReturns, losses, processingIn, processingOut, closing]
          .every((q) => q.birds == 0 && (num.tryParse(q.weight) ?? 0) == 0);
}

class StockRepository {
  StockRepository(this._api);
  final ApiClient _api;

  /// Stock available right now, per chicken type.
  Future<Map<String, BirdsKg>> current() async {
    final res = await _api.get('/stock/current') as Map<String, dynamic>;
    return {for (final e in res.entries) e.key: BirdsKg.fromJson(e.value as Map<String, dynamic>)};
  }

  Future<Map<String, StockTypeSummary>> summary(DayRange r) async {
    final res = await _api.get('/stock/summary', query: {'date_from': r.apiFrom, 'date_to': r.apiTo});
    final types = res['types'] as Map<String, dynamic>;
    return {for (final e in types.entries) e.key: StockTypeSummary(e.value as Map<String, dynamic>)};
  }

  Future<List<Map<String, dynamic>>> transactions(DayRange r) async {
    final res = await _api.get('/stock/transactions', query: {'date_from': r.apiFrom, 'date_to': r.apiTo});
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> recordLoss(Map<String, dynamic> body) => _api.post('/stock/losses', body);
  Future<void> recordProcessing(Map<String, dynamic> body) => _api.post('/stock/processing', body);
}

final stockRepoProvider = Provider((ref) => StockRepository(ref.watch(apiClientProvider)));

final stockSummaryProvider = FutureProvider.autoDispose.family<Map<String, StockTypeSummary>, DayRange>(
  (ref, r) => ref.watch(stockRepoProvider).summary(r),
);

final stockTxnProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, DayRange>(
  (ref, r) => ref.watch(stockRepoProvider).transactions(r),
);

const txnKindLabels = {
  'purchase': 'Received',
  'purchase_cancel': 'Receiving cancelled',
  'delivery': 'Supplied',
  'delivery_cancel': 'Delivery cancelled',
  'customer_return': 'Customer return',
  'supplier_return': 'Returned to supplier',
  'loss': 'Dead / wastage',
  'loss_cancel': 'Loss cancelled',
  'processing_out': 'Sent to processing',
  'processing_in': 'From processing',
  'processing_cancel': 'Processing cancelled',
};

const lossKinds = {'dead': 'Dead', 'damaged': 'Damaged', 'wastage': 'Wastage', 'shortage': 'Shortage'};
