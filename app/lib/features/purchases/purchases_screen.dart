import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/date_range_bar.dart';
import '../auth/auth_controller.dart';
import '../stock/stock.dart';
import 'purchase.dart';
import 'purchase_form.dart';

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});
  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  DayRange _range = DayRange.today();
  bool _showCancelled = false;

  PurchaseQuery get _query => (range: _range, includeCancelled: _showCancelled, q: '');

  void _refreshAll() {
    ref.invalidate(purchaseListProvider);
    ref.invalidate(stockSummaryProvider);
  }

  Future<void> _add() async {
    final p = await showPurchaseForm(context);
    if (p != null && mounted) {
      _refreshAll();
      showSnack(context, '${p.refNo} saved — stock updated');
    }
  }

  Future<void> _cancel(Purchase p) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancel ${p.refNo}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('This removes ${p.birds} birds and ${p.netWeight} KG from stock. '
              'The record is kept in history as cancelled.'),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason *')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.due),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancel purchase'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (reason.text.trim().length < 3) {
      if (mounted) showSnack(context, 'Please enter a reason', error: true);
      return;
    }
    try {
      await ref.read(purchaseRepoProvider).cancel(p.id, reason.text.trim());
      _refreshAll();
      if (mounted) showSnack(context, '${p.refNo} cancelled');
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(currentUserProvider)?.canManage ?? false;
    final data = ref.watch(purchaseListProvider(_query));
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock receiving'),
        actions: [
          if (canManage && wide)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Receive stock')),
            ),
        ],
      ),
      floatingActionButton: canManage && !wide
          ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Receive'))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text(_range.label, style: const TextStyle(color: AppColors.textMuted)),
            const Spacer(),
            const Text('Show cancelled'),
            Switch(value: _showCancelled, onChanged: (v) => setState(() => _showCancelled = v)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: data.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(purchaseListProvider(_query))),
            data: (res) => Column(children: [
              _TotalsStrip(res.totals),
              const Divider(height: 1),
              Expanded(
                child: res.items.isEmpty
                    ? EmptyView(
                        icon: Icons.local_shipping_outlined,
                        message: 'No stock received in this period.',
                        action: canManage
                            ? FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Receive stock'))
                            : null,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: res.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _PurchaseTile(
                          p: res.items[i],
                          onCancel: canManage && !res.items[i].cancelled ? () => _cancel(res.items[i]) : null,
                        ),
                      ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _TotalsStrip extends StatelessWidget {
  const _TotalsStrip(this.t);
  final Map<String, dynamic> t;
  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
        );
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      child: Wrap(children: [
        cell('Entries', '${t['count']}'),
        cell('Birds', '${t['birds']}'),
        cell('Net weight', formatKg('${t['net_weight']}')),
        cell('Purchase amount', formatMoney('${t['amount']}')),
        cell('Total cost', formatMoney('${t['total_cost']}')),
      ]),
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.p, this.onCancel});
  final Purchase p;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final muted = p.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.textMuted) : null;
    return ExpansionTile(
      shape: const Border(),
      leading: CircleAvatar(
        backgroundColor: p.cancelled ? AppColors.surface : AppColors.greenSoft,
        child: Icon(Icons.local_shipping_outlined, color: p.cancelled ? AppColors.textMuted : AppColors.green),
      ),
      title: Text('${p.supplierName} · ${chickenTypes[p.chickenType]}', style: muted ?? const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${p.refNo} · ${formatDate(p.date)}${p.time != null ? ' ${p.time}' : ''}\n'
        '${p.birds} birds · ${formatKg(p.netWeight)} @ Rs ${p.rate} ${rateUnits[p.rateUnit]!.toLowerCase()}',
        style: muted,
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(formatMoney(p.amount), style: muted ?? const TextStyle(fontWeight: FontWeight.w700)),
        if (p.cancelled) const Text('CANCELLED', style: TextStyle(color: AppColors.due, fontSize: 11)),
      ]),
      childrenPadding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gross ${formatKg(p.grossWeight)} · Net ${formatKg(p.netWeight)}'),
        Text('Transport ${formatMoney(p.transport)} · Other ${formatMoney(p.other)} · Total cost ${formatMoney(p.totalCost)}'),
        if (p.supplierRef != null) Text('Supplier ref: ${p.supplierRef}'),
        if (p.notes != null) Text('Notes: ${p.notes}'),
        if (p.cancelled) Text('Cancel reason: ${p.cancelReason ?? '-'}', style: const TextStyle(color: AppColors.due)),
        if (onCancel != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.block, color: AppColors.due, size: 18),
              label: const Text('Cancel entry', style: TextStyle(color: AppColors.due)),
            ),
          ),
      ],
    );
  }
}
