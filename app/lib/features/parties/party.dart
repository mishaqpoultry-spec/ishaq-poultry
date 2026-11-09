import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';

/// Customers and suppliers share one model/screen set; `kind` decides fields.
enum PartyKind {
  customer('/customers', 'Customer', 'Customers', 'Business name'),
  supplier('/suppliers', 'Supplier', 'Suppliers', 'Farm name');

  const PartyKind(this.endpoint, this.singular, this.plural, this.secondaryLabel);
  final String endpoint;
  final String singular;
  final String plural;
  final String secondaryLabel;

  /// What a positive balance means for this party.
  String get balanceLabel => this == PartyKind.customer ? 'Receivable' : 'Payable';
}

const customerTypes = {'shop': 'Shop', 'hotel': 'Hotel', 'restaurant': 'Restaurant', 'other': 'Other'};

class Party {
  Party({
    required this.kind,
    required this.id,
    required this.code,
    required this.name,
    this.secondaryName,
    this.customerType,
    this.phone,
    this.whatsapp,
    this.address,
    required this.openingBalance,
    this.currentBalance,
    required this.status,
    this.notes,
    this.createdAt,
  });

  final PartyKind kind;
  final int id;
  final String code;
  final String name;
  final String? secondaryName; // business name (customer) / farm name (supplier)
  final String? customerType;
  final String? phone;
  final String? whatsapp;
  final String? address;
  final String openingBalance; // decimal string, never double
  final String? currentBalance;
  final String status;
  final String? notes;
  final DateTime? createdAt;

  factory Party.fromJson(PartyKind kind, Map<String, dynamic> j) => Party(
        kind: kind,
        id: j['id'] as int,
        code: j['code'] as String,
        name: j['name'] as String,
        secondaryName: (kind == PartyKind.customer ? j['business_name'] : j['farm_name']) as String?,
        customerType: j['customer_type'] as String?,
        phone: j['phone'] as String?,
        whatsapp: j['whatsapp'] as String?,
        address: j['address'] as String?,
        openingBalance: '${j['opening_balance']}',
        currentBalance: j['current_balance']?.toString(),
        status: j['status'] as String,
        notes: j['notes'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}'),
      );
}

class PartyPage {
  PartyPage(this.items, this.total);
  final List<Party> items;
  final int total;
}

class PartyRepository {
  PartyRepository(this._api);
  final ApiClient _api;

  Future<PartyPage> list(PartyKind kind, {String? q, String? status, int page = 1, int pageSize = 200}) async {
    final r = await _api.get(kind.endpoint, query: {'q': q, 'status': status, 'page': page, 'page_size': pageSize});
    final items = (r['items'] as List).map((e) => Party.fromJson(kind, e as Map<String, dynamic>)).toList();
    return PartyPage(items, r['total'] as int);
  }

  Future<Party> get(PartyKind kind, int id) async =>
      Party.fromJson(kind, await _api.get('${kind.endpoint}/$id') as Map<String, dynamic>);

  Future<Party> create(PartyKind kind, Map<String, dynamic> body) async =>
      Party.fromJson(kind, await _api.post(kind.endpoint, body) as Map<String, dynamic>);

  Future<Party> update(PartyKind kind, int id, Map<String, dynamic> body) async =>
      Party.fromJson(kind, await _api.patch('${kind.endpoint}/$id', body) as Map<String, dynamic>);
}

final partyRepoProvider = Provider((ref) => PartyRepository(ref.watch(apiClientProvider)));

typedef PartyQuery = ({PartyKind kind, String q, String? status});

final partyListProvider = FutureProvider.autoDispose.family<PartyPage, PartyQuery>(
  (ref, query) => ref
      .watch(partyRepoProvider)
      .list(query.kind, q: query.q, status: query.status),
);

final partyDetailProvider = FutureProvider.autoDispose.family<Party, (PartyKind, int)>(
  (ref, key) => ref.watch(partyRepoProvider).get(key.$1, key.$2),
);
