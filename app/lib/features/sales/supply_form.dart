import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/decimal_math.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../parties/party.dart';
import '../purchases/purchase.dart';
import 'sales.dart';

/// Opens the supply sheet. Returns the generated invoice (or null).
/// Pass [customer] when opened from a customer's page.
Future<Invoice?> showSupplyForm(BuildContext context, {Party? customer}) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  final form = _SupplyForm(customer: customer);
  return showDialog<Invoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => wide
        ? Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: form))
        : Dialog.fullscreen(child: form),
  );
}

final _activeCustomersProvider = FutureProvider.autoDispose<List<Party>>((ref) async {
  final page = await ref.watch(partyRepoProvider).list(PartyKind.customer, status: 'active', pageSize: 500);
  return page.items;
});

final _wFmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))];
final _mFmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))];

class _SupplyForm extends ConsumerStatefulWidget {
  const _SupplyForm({this.customer});
  final Party? customer;
  @override
  ConsumerState<_SupplyForm> createState() => _SupplyFormState();
}

class _SupplyFormState extends ConsumerState<_SupplyForm> {
  final _form = GlobalKey<FormState>();
  final _key = newIdempotencyKey();
  Party? _customer;
  String? _previous; // customer's current balance (old udhaar) from server
  bool _loadingBalance = false;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  TimeOfDay _time = TimeOfDay.now();
  String _method = 'cash';
  String? _rateHint;
  final _pieces = TextEditingController();
  final _weight = TextEditingController();
  final _rate = TextEditingController();
  final _discount = TextEditingController(); // per KG
  final _paid = TextEditingController();
  bool _busy = false;
  String? _error; // shown right above the Generate button

  @override
  void initState() {
    super.initState();
    for (final c in [_weight, _rate, _discount, _paid]) {
      c.addListener(() => setState(() {}));
    }
    if (widget.customer != null) _selectCustomer(widget.customer!);
  }

  @override
  void dispose() {
    for (final c in [_pieces, _weight, _rate, _discount, _paid]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _apiDate => DateFormat('yyyy-MM-dd').format(_date);

  Future<void> _selectCustomer(Party c) async {
    setState(() {
      _customer = c;
      _loadingBalance = true;
      _error = null;
    });
    try {
      // Fresh balance (another invoice may have been made since the list loaded).
      final fresh = await ref.read(partyRepoProvider).get(PartyKind.customer, c.id);
      if (mounted) setState(() => _previous = fresh.currentBalance ?? fresh.openingBalance);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
    _loadRate();
  }

  Future<void> _loadRate() async {
    final c = _customer;
    if (c == null) return;
    try {
      final r = await ref.read(salesRepoProvider).applicableRate(c.id, 'live', _apiDate);
      if (!mounted) return;
      setState(() {
        if (r != null && r.unit == 'per_kg') {
          _rate.text = r.rate;
          _rateHint = 'From rate list';
        } else {
          _rateHint = null;
        }
      });
    } catch (_) {
      // Rate lookup is only a convenience; the user can type the rate.
    }
  }

  // --- Exact decimal maths (same rounding as the server) -------------------

  Dec get _zero => Dec.zero();
  Dec? get _kg => Dec.tryParse(_weight.text, scale: 3);
  Dec? get _rateDec => Dec.tryParse(_rate.text, scale: 2);
  Dec get _discPerKg => Dec.tryParse(_discount.text, scale: 2) ?? _zero;
  Dec get _paidDec => Dec.tryParse(_paid.text, scale: 2) ?? _zero;
  Dec? get _prev => Dec.tryParse(_previous, scale: 2);

  Dec? get _supplyAmount => (_kg == null || _rateDec == null) ? null : (_rateDec! * _kg!).round(2);
  Dec? get _discountTotal => _kg == null ? null : (_discPerKg * _kg!).round(2);
  Dec? get _afterDiscount =>
      (_supplyAmount == null || _discountTotal == null) ? null : _supplyAmount! - _discountTotal!;

  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _error = null);
    if (_customer == null) {
      setState(() => _error = 'Select a customer');
      return;
    }
    if (!_form.currentState!.validate()) {
      setState(() => _error = 'Please fill the fields marked in red');
      return;
    }
    if (_rateDec != null && _discPerKg.compareTo(_rateDec!) > 0) {
      setState(() => _error = 'Discount per KG cannot be more than the rate');
      return;
    }
    final body = {
      'idempotency_key': _key,
      'customer_id': _customer!.id,
      'delivery_date': _apiDate,
      'delivery_time': '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00',
      'chicken_type': 'live',
      'birds': int.tryParse(_pieces.text) ?? 0,
      'net_weight': _weight.text.trim(),
      'rate': _rate.text.trim(),
      'rate_unit': 'per_kg',
      'discount_per_kg': _discount.text.trim().isEmpty ? '0' : _discount.text.trim(),
      'payment_received': _paid.text.trim().isEmpty ? '0' : _paid.text.trim(),
      'payment_method': _method,
    };
    setState(() => _busy = true);
    try {
      final inv = await ref.read(salesRepoProvider).createDelivery(body);
      if (mounted) Navigator.pop(context, inv);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    const hgap = SizedBox(width: 12);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('New Supply / Invoice'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.due, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.due))),
                ]),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.receipt_long),
              label: const Text('Generate Invoice', style: TextStyle(fontSize: 16)),
            ),
          ]),
        ),
      ),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.customer == null)
              ref.watch(_activeCustomersProvider).when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.due)),
                    data: (list) => DropdownButtonFormField<int>(
                      initialValue: _customer?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Customer *'),
                      items: [
                        for (final c in list)
                          DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (id) => _selectCustomer(list.firstWhere((c) => c.id == id)),
                      validator: (v) => v == null ? 'Select a customer' : null,
                    ),
                  )
            else
              Text(widget.customer!.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            gap,
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (d != null) {
                      setState(() => _date = d);
                      _loadRate();
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.event)),
                    child: Text(formatDate(_date)),
                  ),
                ),
              ),
              hgap,
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _time);
                    if (t != null) setState(() => _time = t);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Time', suffixIcon: Icon(Icons.schedule)),
                    child: Text(_time.format(context)),
                  ),
                ),
              ),
            ]),
            gap,
            const Text('Live Chicken', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.green)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _pieces,
                  decoration: const InputDecoration(labelText: 'Pieces'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              hgap,
              Expanded(
                child: TextFormField(
                  controller: _weight,
                  decoration: const InputDecoration(labelText: 'Total weight (KG) *'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _wFmt,
                  validator: (v) => (Dec.tryParse(v)?.isZero ?? true) ? 'Required' : null,
                ),
              ),
            ]),
            gap,
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _rate,
                  decoration: InputDecoration(labelText: 'Rate per KG (Rs) *', helperText: _rateHint),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _mFmt,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              hgap,
              Expanded(
                child: TextFormField(
                  controller: _discount,
                  decoration: const InputDecoration(labelText: 'Discount per KG (Rs)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _mFmt,
                ),
              ),
            ]),
            gap,
            Row(children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _paid,
                  decoration: const InputDecoration(labelText: 'Payment received (Rs)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _mFmt,
                ),
              ),
              hgap,
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _method,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: [for (final e in paymentMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _method = v ?? 'cash'),
                ),
              ),
            ]),
            gap,
            _Summary(
              loading: _loadingBalance,
              previous: _prev,
              kg: _weight.text,
              rate: _rate.text,
              discPerKg: _discPerKg,
              supply: _supplyAmount,
              discount: _discountTotal,
              after: _afterDiscount,
              paid: _paidDec,
            ),
          ]),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.loading,
    required this.previous,
    required this.kg,
    required this.rate,
    required this.discPerKg,
    required this.supply,
    required this.discount,
    required this.after,
    required this.paid,
  });
  final bool loading;
  final Dec? previous;
  final String kg;
  final String rate;
  final Dec discPerKg;
  final Dec? supply;
  final Dec? discount;
  final Dec? after;
  final Dec paid;

  @override
  Widget build(BuildContext context) {
    String m(Dec? v) => v == null ? '—' : formatMoney(v.toString());
    final total = (previous != null && after != null) ? previous! + after! : null;
    final remaining = total == null ? null : total - paid;

    Widget line(String label, String value, {Color? color, bool bold = false, double size = 14}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
                child: Text(label, style: TextStyle(color: bold ? AppColors.text : AppColors.textMuted, fontSize: size))),
            Text(value, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: size)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        line('Supply: ${kg.isEmpty ? 0 : kg} KG × Rs ${rate.isEmpty ? 0 : rate}', m(supply)),
        if (!discPerKg.isZero) line('Discount: Rs $discPerKg per KG × ${kg.isEmpty ? 0 : kg} KG', '− ${m(discount)}', color: AppColors.due),
        line('Amount after discount', m(after), bold: true),
        const Divider(),
        line('Previous balance (old udhaar)', loading ? '...' : m(previous),
            color: (previous != null && !previous!.isNegative && !previous!.isZero) ? AppColors.due : null),
        line('Total payable', m(total), bold: true),
        line('Payment received', m(paid), color: AppColors.paid),
        const Divider(),
        line('Remaining balance', m(remaining),
            bold: true,
            size: 18,
            color: remaining == null ? null : (remaining.isNegative || remaining.isZero ? AppColors.paid : AppColors.due)),
      ]),
    );
  }
}
