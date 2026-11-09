import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/decimal_math.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/date_range_bar.dart';
import '../auth/auth_controller.dart';
import '../purchases/purchase.dart';
import 'stock.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  DayRange _range = DayRange.today();

  void _refresh() {
    ref.invalidate(stockSummaryProvider);
    ref.invalidate(stockTxnProvider);
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(currentUserProvider)?.canManage ?? false;
    final summary = ref.watch(stockSummaryProvider(_range));
    final txns = ref.watch(stockTxnProvider(_range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock / Inventory'),
        actions: [
          if (canManage) ...[
            TextButton.icon(
              icon: const Icon(Icons.heart_broken_outlined),
              label: const Text('Dead / wastage'),
              onPressed: () async {
                if (await showDialog<bool>(context: context, builder: (_) => const _LossDialog()) == true) _refresh();
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.restaurant_outlined),
              label: const Text('Processing'),
              onPressed: () async {
                if (await showDialog<bool>(context: context, builder: (_) => const _ProcessingDialog()) == true) {
                  _refresh();
                }
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
          const SizedBox(height: 8),
          Text(_range.label, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          summary.when(
            loading: () => const Padding(padding: EdgeInsets.all(40), child: LoadingView()),
            error: (e, _) => ErrorView(error: e, onRetry: _refresh),
            data: (types) {
              final shown = types.entries.where((e) => e.key == 'live' || !e.value.isEmpty).toList();
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final e in shown) _TypeCard(type: e.key, s: e.value),
              ]);
            },
          ),
          const SizedBox(height: 24),
          Text('Stock movements', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          txns.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.due)),
            data: (list) => list.isEmpty
                ? const EmptyView(icon: Icons.swap_vert, message: 'No stock movement in this period.')
                : Card(
                    child: Column(children: [
                      for (final t in list) _TxnRow(t),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.s});
  final String type;
  final StockTypeSummary s;

  @override
  Widget build(BuildContext context) {
    TableRow row(String label, BirdsKg q, {bool bold = false, Color? color, String sign = ''}) {
      final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color);
      return TableRow(children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(label, style: style)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('$sign${q.birds}', textAlign: TextAlign.right, style: style),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('$sign${formatKg(q.weight)}', textAlign: TextAlign.right, style: style),
        ),
      ]);
    }

    final divider = TableRow(children: List.generate(3, (_) => const Divider(height: 8)));
    return SizedBox(
      width: 420,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${chickenTypes[type] ?? type} chicken',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(20)),
                child: Text('${s.closing.birds} birds · ${formatKg(s.closing.weight)}',
                    style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 10),
            Table(
              columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.6)},
              children: [
                const TableRow(children: [
                  Text('', style: TextStyle(color: AppColors.textMuted)),
                  Text('Birds', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted)),
                  Text('Weight', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted)),
                ]),
                row('Opening stock', s.opening),
                row('Received', s.received, sign: '+ ', color: AppColors.green),
                if (s.processingIn.birds != 0 || s.processingIn.weight != '0.000')
                  row('From processing', s.processingIn, sign: '+ ', color: AppColors.green),
                row('Customer returns', s.customerReturns, sign: '+ '),
                row('Supplied', s.supplied, sign: '− '),
                if (s.processingOut.birds != 0 || s.processingOut.weight != '0.000')
                  row('To processing', s.processingOut, sign: '− '),
                if (s.supplierReturns.birds != 0 || s.supplierReturns.weight != '0.000')
                  row('Returned to supplier', s.supplierReturns, sign: '− '),
                row('Dead / wastage', s.losses, sign: '− ', color: AppColors.due),
                divider,
                row('Closing stock', s.closing, bold: true),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow(this.t);
  final Map<String, dynamic> t;
  @override
  Widget build(BuildContext context) {
    final birds = t['birds'] as int;
    final w = '${t['weight']}';
    final inbound = (num.tryParse(w) ?? 0) > 0 || birds > 0;
    String signed(String v) => (num.tryParse(v) ?? 0) > 0 ? '+$v' : v;
    return ListTile(
      dense: true,
      leading: Icon(inbound ? Icons.arrow_downward : Icons.arrow_upward,
          color: inbound ? AppColors.green : AppColors.due, size: 20),
      title: Text('${txnKindLabels[t['kind']] ?? t['kind']} · ${chickenTypes[t['chicken_type']]}'),
      subtitle: Text([
        t['ref_no'] ?? '',
        formatDate(DateTime.tryParse('${t['txn_date']}')),
        if (t['notes'] != null && '${t['notes']}'.isNotEmpty) '${t['notes']}',
      ].join(' · ')),
      trailing: Text('${signed('$birds')} birds   ${signed(w)} KG',
          style: TextStyle(color: inbound ? AppColors.green : AppColors.due, fontWeight: FontWeight.w600)),
    );
  }
}

// --- Dialogs ---------------------------------------------------------------

final _wFmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))];
String _api(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final d = await showDatePicker(
              context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime.now());
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.event)),
          child: Text(formatDate(value)),
        ),
      );
}

class _LossDialog extends ConsumerStatefulWidget {
  const _LossDialog();
  @override
  ConsumerState<_LossDialog> createState() => _LossDialogState();
}

class _LossDialogState extends ConsumerState<_LossDialog> {
  final _form = GlobalKey<FormState>();
  final _key = newIdempotencyKey();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String _type = 'live';
  String _kind = 'dead';
  final _birds = TextEditingController();
  final _weight = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final birds = int.tryParse(_birds.text) ?? 0;
    final weight = _weight.text.trim().isEmpty ? '0' : _weight.text.trim();
    if (birds == 0 && (Dec.tryParse(weight)?.isZero ?? true)) {
      showSnack(context, 'Enter birds or weight', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(stockRepoProvider).recordLoss({
        'idempotency_key': _key,
        'loss_date': _api(_date),
        'chicken_type': _type,
        'kind': _kind,
        'birds': birds,
        'weight': weight,
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context, true);
        showSnack(context, 'Recorded — stock reduced');
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: const Text('Dead / damaged / wastage'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
              gap,
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Chicken type'),
                    items: [for (final e in chickenTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: 'Type of loss'),
                    items: [for (final e in lossKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _kind = v!),
                  ),
                ),
              ]),
              gap,
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _birds,
                    decoration: const InputDecoration(labelText: 'Birds'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _weight,
                    decoration: const InputDecoration(labelText: 'Weight (KG)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _wFmt,
                  ),
                ),
              ]),
              gap,
              TextFormField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason / notes')),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

class _ProcessingDialog extends ConsumerStatefulWidget {
  const _ProcessingDialog();
  @override
  ConsumerState<_ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends ConsumerState<_ProcessingDialog> {
  final _form = GlobalKey<FormState>();
  final _key = newIdempotencyKey();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String _output = 'dressed';
  final _inBirds = TextEditingController();
  final _inWeight = TextEditingController();
  final _outWeight = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _inWeight.addListener(() => setState(() {}));
    _outWeight.addListener(() => setState(() {}));
  }

  String get _preview {
    final i = Dec.tryParse(_inWeight.text);
    final o = Dec.tryParse(_outWeight.text);
    if (i == null || o == null || i.isZero) return '';
    final wastage = i - o;
    // Both weights have scale 3, so units ratio == weight ratio. Hundredths of a percent:
    final yieldPct = (o.units * BigInt.from(10000) ~/ i.units).toInt() / 100;
    return 'Wastage ${formatKg(wastage.toString())} · Yield ${yieldPct.toStringAsFixed(2)}%';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(stockRepoProvider).recordProcessing({
        'idempotency_key': _key,
        'process_date': _api(_date),
        'input_type': 'live',
        'output_type': _output,
        'input_birds': int.parse(_inBirds.text),
        'input_weight': _inWeight.text.trim(),
        'output_weight': _outWeight.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context, true);
        showSnack(context, 'Processing recorded');
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: const Text('Live → dressed / cleaned'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
              gap,
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'dressed', label: Text('Dressed')),
                  ButtonSegment(value: 'cleaned', label: Text('Cleaned')),
                ],
                selected: {_output},
                onSelectionChanged: (s) => setState(() => _output = s.first),
              ),
              gap,
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _inBirds,
                    decoration: const InputDecoration(labelText: 'Live birds used *'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _inWeight,
                    decoration: const InputDecoration(labelText: 'Live weight (KG) *'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _wFmt,
                    validator: (v) => (Dec.tryParse(v)?.isZero ?? true) ? 'Required' : null,
                  ),
                ),
              ]),
              gap,
              TextFormField(
                controller: _outWeight,
                decoration: InputDecoration(labelText: 'Output $_output weight (KG) *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _wFmt,
                validator: (v) {
                  final o = Dec.tryParse(v);
                  if (o == null || o.isZero) return 'Required';
                  final i = Dec.tryParse(_inWeight.text);
                  if (i != null && o.compareTo(i) > 0) return 'Cannot exceed live weight';
                  return null;
                },
              ),
              if (_preview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: Text(_preview, style: const TextStyle(color: AppColors.green))),
              ],
              gap,
              TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
