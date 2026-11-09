import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.00', 'en_US');
final _date = DateFormat('dd MMM yyyy');

/// Amounts come from the API as decimal strings; never parse them to double
/// for arithmetic. Only format for display.
String formatMoney(String? value) {
  if (value == null || value.isEmpty) return 'Rs 0.00';
  final n = num.tryParse(value);
  return n == null ? 'Rs $value' : 'Rs ${_money.format(n)}';
}

final _kg = NumberFormat('#,##0.000', 'en_US');

String formatKg(String? value) {
  final n = num.tryParse(value ?? '');
  return n == null ? '0.000 KG' : '${_kg.format(n)} KG';
}

String formatDate(DateTime? d) => d == null ? '-' : _date.format(d.toLocal());

bool isPositiveAmount(String? value) => (num.tryParse(value ?? '') ?? 0) > 0;
