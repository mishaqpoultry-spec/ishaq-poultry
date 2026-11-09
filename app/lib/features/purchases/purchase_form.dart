import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/decimal_math.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../parties/party.dart';
import 'purchase.dart';

Future<Purchase?> showPurchaseForm(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  const form = _PurchaseForm();
  return showDialog<Purchase>(
    context: context,
    barrierDismissible: false,
    builder: (_) => wide
        ? Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: form))
        : Dialog.fullscreen(child: form),
  );
}

final _activeSuppliersProvider = FutureProvider.autoDispose<List<Party>>((ref) async {
  final page = await ref.watch(partyRepoProvider).list(PartyKind.supplier, status: 'active', pageSize: 500);
  return page.items;
});

final _weightFmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))];
final _moneyFmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))];

class _PurchaseForm extends ConsumerStatefulWidget {
  const _PurchaseForm();
  @override
  ConsumerState<_PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends ConsumerState<_PurchaseForm> {
  final _form = GlobalKey<FormState>();
  final _key = newIdempotencyKey();
  int? _supplierId;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  TimeOfDay _time = TimeOfDay.now();
  String _type = 'live';
  String _unit = 'per_kg';
  final _birds = TextEditingController();
  final _gross = TextEditingController();
  final _net = TextEditingController();
  final _rate = TextEditingController();
  final _transport = TextEditingController(text: '0');
  final _other = TextEditingController(text: '0');
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_birds, _net, _rate, _transport, _other]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_birds, _gross, _net, _rate, _transport, _other, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Dec? get _amount {
    final rate = Dec.tryParse(_rate.text, scale: 2);
    if (rate == null) return null;
    final qty = _unit == 'per_kg' ? Dec.tryParse(_net.text, scale: 3) : Dec.tryParse(_birds.text, scale: 0);
    if (qty == null) return null;
    return (rate * qty).round(2);
  }

  Dec? get _totalCost {
    final a = _amount;
    if (a == null) return null;
    final t = Dec.tryParse(_transport.text, scale: 2) ?? Dec.zero();
    final o = Dec.tryParse(_other.text, scale: 2) ?? Dec.zero();
    return a + t + o;
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    final body = {
      'idempotency_key': _key,
      'supplier_id': _supplierId,
      'purchase_date': DateFormat('yyyy-MM-dd').format(_date),
      'receiving_time': '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00',
      'chicken_type': _type,
      'birds': int.tryParse(_birds.text) ?? 0,
      'gross_weight': _gross.text.trim(),
      'net_weight': _net.text.trim(),
      'rate': _rate.text.trim(),
      'rate_unit': _unit,
      'transport_charges': _transport.text.trim().isEmpty ? '0' : _transport.text.trim(),
      'other_expenses': _other.text.trim().isEmpty ? '0' : _other.text.trim(),
      'supplier_ref': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    setState(() => _busy = true);
    try {
      final p = await ref.read(purchaseRepoProvider).create(body);
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(_activeSuppliersProvider);
    const gap = SizedBox(height: 14);
    const hgap = SizedBox(width: 12);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Stock receiving'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          suppliers.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.due)),
            data: (list) => list.isEmpty
                ? const Text('No active suppliers. Add a supplier first.', style: TextStyle(color: AppColors.due))
                : DropdownButtonFormField<int>(
                    initialValue: _supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Supplier / farm *'),
                    items: [
                      for (final s in list)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text([s.name, if (s.secondaryName != null) s.secondaryName!].join(' — '),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                    validator: (v) => v == null ? 'Select supplier' : null,
                  ),
          ),
          gap,
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (d != null) setState(() => _date = d);
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
                  decoration: const InputDecoration(labelText: 'Receiving time', suffixIcon: Icon(Icons.schedule)),
                  child: Text(_time.format(context)),
                ),
              ),
            ),
          ]),
          gap,
          SegmentedButton<String>(
            segments: [for (final e in chickenTypes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          gap,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _birds,
                decoration: const InputDecoration(labelText: 'Number of birds'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = int.tryParse(v ?? '') ?? 0;
                  if ((_type == 'live' || _unit == 'per_bird') && n <= 0) return 'Birds required';
                  return null;
                },
              ),
            ),
            hgap,
            Expanded(
              child: TextFormField(
                controller: _gross,
                decoration: const InputDecoration(labelText: 'Gross weight (KG) *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _weightFmt,
                validator: _required,
              ),
            ),
            hgap,
            Expanded(
              child: TextFormField(
                controller: _net,
                decoration: const InputDecoration(labelText: 'Net weight (KG) *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _weightFmt,
                validator: (v) {
                  final n = Dec.tryParse(v);
                  if (n == null || n.isZero) return 'Required';
                  final g = Dec.tryParse(_gross.text);
                  if (g != null && n.compareTo(g) > 0) return 'More than gross';
                  return null;
                },
              ),
            ),
          ]),
          gap,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _rate,
                decoration: const InputDecoration(labelText: 'Purchase rate (Rs) *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _moneyFmt,
                validator: _required,
              ),
            ),
            hgap,
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Rate unit'),
                items: [for (final e in rateUnits.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _unit = v ?? 'per_kg'),
              ),
            ),
          ]),
          gap,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _transport,
                decoration: const InputDecoration(labelText: 'Transport charges (Rs)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _moneyFmt,
              ),
            ),
            hgap,
            Expanded(
              child: TextFormField(
                controller: _other,
                decoration: const InputDecoration(labelText: 'Other expenses (Rs)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _moneyFmt,
              ),
            ),
          ]),
          gap,
          _TotalsBox(amount: _amount, totalCost: _totalCost, unit: _unit),
          gap,
          TextFormField(
            controller: _ref,
            decoration: const InputDecoration(labelText: 'Supplier bill / reference no.'),
            maxLength: 60,
          ),
          TextFormField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 2,
            maxLength: 2000,
          ),
        ]),
        ),
      ),
    );
  }
}

class _TotalsBox extends StatelessWidget {
  const _TotalsBox({required this.amount, required this.totalCost, required this.unit});
  final Dec? amount;
  final Dec? totalCost;
  final String unit;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, Dec? v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: TextStyle(color: bold ? AppColors.text : AppColors.textMuted)),
            Text(v == null ? '—' : formatMoney(v.toString()),
                style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 17 : 14)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        line(unit == 'per_kg' ? 'Amount (net KG × rate) — payable to supplier' : 'Amount (birds × rate) — payable to supplier',
            amount, bold: true),
        line('Total batch cost (incl. transport & other)', totalCost),
      ]),
    );
  }
}
