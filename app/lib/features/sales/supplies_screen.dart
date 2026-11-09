import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/date_range_bar.dart';
import '../auth/auth_controller.dart';
import '../parties/party.dart';
import '../purchases/purchase.dart';
import '../stock/stock.dart';
import 'invoice_share_sheet.dart';
import 'sales.dart';
import 'supply_form.dart';

/// All supplies / invoices for a period, with totals.
class SuppliesScreen extends ConsumerStatefulWidget {
  const SuppliesScreen({super.key});
  @override
  ConsumerState<SuppliesScreen> createState() => _SuppliesScreenState();
}

class _SuppliesScreenState extends ConsumerState<SuppliesScreen> {
  DayRange _range = DayRange.today();
  bool _showCancelled = false;

  DeliveryQuery get _q => (range: _range, customerId: null, includeCancelled: _showCancelled);

  Future<void> _new() async {
    final inv = await showSupplyForm(context);
    if (inv == null || !mounted) return;
    refreshAfterInvoiceChange(ref);
    await showInvoiceShareSheet(context, inv, justCreated: true);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(deliveryListProvider(_q));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supply / Invoices'),
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('Nayi supply')),
            ),
        ],
      ),
      floatingActionButton:
          wide ? null : FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add), label: const Text('Supply')),
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
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(deliveryListProvider(_q))),
            data: (res) => Column(children: [
              Container(
                width: double.infinity,
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Wrap(children: [
                  _cell('Invoices', '${res.totals['count']}'),
                  _cell('Birds', '${res.totals['birds']}'),
                  _cell('Weight', formatKg('${res.totals['net_weight']}')),
                  _cell('Total bill', formatMoney('${res.totals['total_amount']}')),
                  _cell('Wusool', formatMoney('${res.totals['payment_received']}'), color: AppColors.paid),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: res.items.isEmpty
                    ? EmptyView(
                        icon: Icons.receipt_long_outlined,
                        message: 'Is period mein koi supply nahi.',
                        action: FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('Nayi supply')),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: res.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => InvoiceTile(inv: res.items[i]),
                      ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _cell(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
        ]),
      );
}

/// Refresh every screen that shows balances, stock or invoices.
void refreshAfterInvoiceChange(WidgetRef ref) {
  ref.invalidate(deliveryListProvider);
  ref.invalidate(ledgerProvider);
  ref.invalidate(partyDetailProvider);
  ref.invalidate(partyListProvider);
  ref.invalidate(stockSummaryProvider);
  ref.invalidate(stockTxnProvider);
}

class InvoiceTile extends ConsumerWidget {
  const InvoiceTile({super.key, required this.inv});
  final Invoice inv;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancel ${inv.invoiceNo}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Stock wapas aa jayega aur is invoice ke saath li gayi payment bhi cancel ho jayegi. '
              'Record history mein rahega.'),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason *')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.due),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancel invoice'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (reason.text.trim().length < 3) {
      if (context.mounted) showSnack(context, 'Reason likhein', error: true);
      return;
    }
    try {
      await ref.read(salesRepoProvider).cancelDelivery(inv.id, reason.text.trim());
      refreshAfterInvoiceChange(ref);
      if (context.mounted) showSnack(context, '${inv.invoiceNo} cancelled');
    } catch (e) {
      if (context.mounted) showSnack(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(currentUserProvider)?.canManage ?? false;
    final muted = inv.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.textMuted) : null;
    return ListTile(
      onTap: () => showInvoiceShareSheet(context, inv),
      leading: CircleAvatar(
        backgroundColor: inv.cancelled ? AppColors.surface : AppColors.greenSoft,
        child: Icon(Icons.receipt_long, color: inv.cancelled ? AppColors.textMuted : AppColors.green),
      ),
      title: Text(inv.customerName, style: muted ?? const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${inv.invoiceNo} · ${formatDate(inv.date)}${inv.time != null ? ' ${inv.time}' : ''}\n'
        '${chickenTypes[inv.chickenType]} · ${inv.birds} birds · ${formatKg(inv.netWeight)} @ Rs ${inv.rate}',
        style: muted,
      ),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatMoney(inv.total), style: muted ?? const TextStyle(fontWeight: FontWeight.w700)),
          if (inv.cancelled)
            const Text('CANCELLED', style: TextStyle(color: AppColors.due, fontSize: 11))
          else
            Text('Baqaya ${formatMoney(inv.balanceAfter)}',
                style: TextStyle(fontSize: 12, color: isPositiveAmount(inv.balanceAfter) ? AppColors.due : AppColors.paid)),
        ]),
        if (canManage && !inv.cancelled)
          PopupMenuButton<String>(
            onSelected: (v) => v == 'cancel' ? _cancel(context, ref) : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancel invoice'))],
          ),
      ]),
    );
  }
}
