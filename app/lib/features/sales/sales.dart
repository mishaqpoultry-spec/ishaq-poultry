import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../widgets/date_range_bar.dart';
import '../auth/auth_controller.dart';

const paymentMethods = {'cash': 'Cash', 'bank': 'Bank transfer', 'online': 'Online', 'other': 'Other'};

/// One supply = one invoice. Amounts are decimal strings from the server.
class Invoice {
  Invoice(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String get invoiceNo => j['invoice_no'] as String;
  int get customerId => j['customer']['id'] as int;
  String get customerName => j['customer']['name'] as String;
  String? get whatsapp => (j['customer']['whatsapp'] ?? j['customer']['phone']) as String?;
  String? get phone => j['customer']['phone'] as String?;
  DateTime get date => DateTime.parse(j['delivery_date'] as String);
  String? get time => (j['delivery_time'] as String?)?.substring(0, 5);
  String get chickenType => j['chicken_type'] as String;
  int get birds => j['birds'] as int;
  String get netWeight => '${j['net_weight']}';
  String get rate => '${j['rate']}';
  String get rateUnit => j['rate_unit'] as String;
  String get amount => '${j['amount']}';
  String get discountPerKg => '${j['discount_per_kg'] ?? '0'}';
  String get discount => '${j['discount']}';
  String get charges => '${j['additional_charges']}';
  String get total => '${j['total_amount']}';
  String get previousBalance => '${j['previous_balance']}';
  String get paymentReceived => '${j['payment_received']}';
  String get balanceAfter => '${j['balance_after']}';
  bool get cancelled => j['status'] == 'cancelled';
}

class LedgerEntry {
  LedgerEntry(this.j);
  final Map<String, dynamic> j;
  DateTime get date => DateTime.parse(j['date'] as String);
  String get kind => j['kind'] as String;
  String get refNo => j['ref_no'] as String;
  int get refId => j['ref_id'] as int;
  String get description => j['description'] as String;
  String get debit => '${j['debit']}';
  String get credit => '${j['credit']}';
  String get balance => '${j['balance']}';
}

class Ledger {
  Ledger(this.j) : entries = (j['entries'] as List).map((e) => LedgerEntry(e as Map<String, dynamic>)).toList();
  final Map<String, dynamic> j;
  final List<LedgerEntry> entries;
  String get opening => '${j['opening_balance']}';
  String get closing => '${j['closing_balance']}';
  String get totalDebit => '${j['total_debit']}';
  String get totalCredit => '${j['total_credit']}';
  int get totalBirds => j['total_birds'] as int;
  String get totalWeight => '${j['total_weight']}';
}

class SalesRepository {
  SalesRepository(this._api);
  final ApiClient _api;

  Future<Invoice> createDelivery(Map<String, dynamic> body) async =>
      Invoice(await _api.post('/deliveries', body) as Map<String, dynamic>);

  Future<Invoice> getDelivery(int id) async => Invoice(await _api.get('/deliveries/$id') as Map<String, dynamic>);

  Future<({List<Invoice> items, Map<String, dynamic> totals})> listDeliveries(DayRange r,
      {int? customerId, bool includeCancelled = false}) async {
    final res = await _api.get('/deliveries', query: {
      'date_from': r.apiFrom,
      'date_to': r.apiTo,
      'customer_id': customerId,
      'include_cancelled': includeCancelled,
    });
    return (
      items: (res['items'] as List).map((e) => Invoice(e as Map<String, dynamic>)).toList(),
      totals: res['totals'] as Map<String, dynamic>,
    );
  }

  Future<void> cancelDelivery(int id, String reason) => _api.post('/deliveries/$id/cancel', {'reason': reason});

  /// Invoice text: [text] for WhatsApp (emoji, bold), [smsText] plain for SMS.
  Future<({String text, String smsText, String? whatsapp, String? phone})> message(int id) async {
    final r = await _api.get('/deliveries/$id/message');
    return (
      text: r['text'] as String,
      smsText: (r['sms_text'] ?? r['text']) as String,
      whatsapp: r['whatsapp'] as String?,
      phone: r['phone'] as String?,
    );
  }

  Future<List<int>> invoicePdf(int id) => _api.getBytes('/deliveries/$id/pdf');

  /// Applicable selling rate for a customer on a date (customer rate, else default). Null if none set.
  Future<({String rate, String unit})?> applicableRate(int customerId, String chickenType, String onDate) async {
    final r = await _api.get('/rates/applicable', query: {'customer_id': customerId, 'chicken_type': chickenType, 'on': onDate});
    if (r == null) return null;
    return (rate: '${r['rate']}', unit: r['rate_unit'] as String);
  }

  Future<List<Map<String, dynamic>>> rates({int? customerId, bool defaultsOnly = false}) async {
    final r = await _api.get('/rates', query: {'customer_id': customerId, 'defaults_only': defaultsOnly});
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> addRate(Map<String, dynamic> body) => _api.post('/rates', body);

  Future<void> addPayment(Map<String, dynamic> body) => _api.post('/payments', body);

  Future<Ledger> ledger(int customerId, DayRange r) async => Ledger(
      await _api.get('/customers/$customerId/ledger', query: {'date_from': r.apiFrom, 'date_to': r.apiTo})
          as Map<String, dynamic>);
}

final salesRepoProvider = Provider((ref) => SalesRepository(ref.watch(apiClientProvider)));

typedef DeliveryQuery = ({DayRange range, int? customerId, bool includeCancelled});

final deliveryListProvider =
    FutureProvider.autoDispose.family<({List<Invoice> items, Map<String, dynamic> totals}), DeliveryQuery>(
  (ref, q) => ref.watch(salesRepoProvider).listDeliveries(q.range, customerId: q.customerId, includeCancelled: q.includeCancelled),
);

final ledgerProvider = FutureProvider.autoDispose.family<Ledger, (int, DayRange)>(
  (ref, k) => ref.watch(salesRepoProvider).ledger(k.$1, k.$2),
);

final ratesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(salesRepoProvider).rates(),
);
