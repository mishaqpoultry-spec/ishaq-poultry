import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/auth_controller.dart';
import '../parties/party.dart';
import '../purchases/purchase.dart';
import 'sales.dart';

final _customersProvider = FutureProvider.autoDispose<List<Party>>((ref) async =>
    (await ref.watch(partyRepoProvider).list(PartyKind.customer, pageSize: 500)).items);

/// Selling rates. A new rate is a new row from its date onward; old invoices
/// keep the rate they were made with.
class RatesScreen extends ConsumerWidget {
  const RatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(currentUserProvider)?.canManage ?? false;
    final rates = ref.watch(ratesProvider);
    final customers = ref.watch(_customersProvider).value ?? const <Party>[];
    String customerName(int? id) =>
        id == null ? 'Sab customers (default)' : customers.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '#$id';

    Future<void> add() async {
      if (await showDialog<bool>(context: context, builder: (_) => const _RateDialog()) == true) {
        ref.invalidate(ratesProvider);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rates'),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Naya rate')),
            ),
        ],
      ),
      body: rates.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(ratesProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyView(
              icon: Icons.sell_outlined,
              message: 'Abhi koi rate set nahi.\nDefault rate set karein — supply form mein khud aa jayega.',
              action: canManage ? FilledButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Naya rate')) : null,
            );
          }
          // Latest rate per (customer, type) is the one currently in effect.
          final seen = <String>{};
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = list[i];
              final key = '${r['customer_id']}-${r['chicken_type']}';
              final today = DateTime.now();
              final eff = DateTime.parse(r['effective_from'] as String);
              final current = !eff.isAfter(today) && seen.add(key);
              return ListTile(
                leading: Icon(Icons.sell_outlined, color: current ? AppColors.green : AppColors.textMuted),
                title: Text('${customerName(r['customer_id'] as int?)} · ${chickenTypes[r['chicken_type']]}'),
                subtitle: Text('${formatDate(eff)} se${r['notes'] != null ? ' · ${r['notes']}' : ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${formatMoney('${r['rate']}')} ${rateUnits[r['rate_unit']]!.toLowerCase()}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: current ? AppColors.text : AppColors.textMuted)),
                  if (current) ...[
                    const SizedBox(width: 8),
                    const Chip(label: Text('Current'), visualDensity: VisualDensity.compact),
                  ],
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class _RateDialog extends ConsumerStatefulWidget {
  const _RateDialog();
  @override
  ConsumerState<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends ConsumerState<_RateDialog> {
  final _form = GlobalKey<FormState>();
  int? _customerId;
  String _type = 'live';
  String _unit = 'per_kg';
  DateTime _from = DateUtils.dateOnly(DateTime.now());
  final _rate = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(salesRepoProvider).addRate({
        'customer_id': _customerId,
        'chicken_type': _type,
        'rate_unit': _unit,
        'rate': _rate.text.trim(),
        'effective_from': DateFormat('yyyy-MM-dd').format(_from),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(_customersProvider).value ?? const <Party>[];
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: const Text('Naya selling rate'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int?>(
              initialValue: _customerId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kis ke liye'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sab customers (default rate)')),
                for (final c in customers) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _customerId = v),
            ),
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
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Per'),
                  items: [for (final e in rateUnits.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _unit = v!),
                ),
              ),
            ]),
            gap,
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _rate,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Rate (Rs) *'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context, initialDate: _from, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => _from = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Kab se'),
                    child: Text(formatDate(_from)),
                  ),
                ),
              ),
            ]),
            gap,
            TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
