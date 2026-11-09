import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/date_range_bar.dart';
import '../parties/party.dart';
import 'invoice_share_sheet.dart';
import 'payment_dialog.dart';
import 'sales.dart';
import 'supplies_screen.dart';
import 'supply_form.dart';

/// "Nayi supply" / "Payment" buttons for the customer page.
class CustomerSalesActions extends ConsumerWidget {
  const CustomerSalesActions(this.customer, {super.key});
  final Party customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = customer.status == 'active';
    return Wrap(spacing: 10, runSpacing: 10, children: [
      FilledButton.icon(
        onPressed: !active
            ? null
            : () async {
                final inv = await showSupplyForm(context, customer: customer);
                if (inv == null || !context.mounted) return;
                refreshAfterInvoiceChange(ref);
                await showInvoiceShareSheet(context, inv, justCreated: true);
              },
        icon: const Icon(Icons.receipt_long),
        label: const Text('Nayi supply / Invoice'),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          if (await showPaymentDialog(context, customer)) {
            refreshAfterInvoiceChange(ref);
            if (context.mounted) showSnack(context, 'Payment saved');
          }
        },
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Payment'),
      ),
    ]);
  }
}

/// Date-wise account ledger with running balance for any period.
class CustomerLedgerCard extends ConsumerStatefulWidget {
  const CustomerLedgerCard(this.customer, {super.key});
  final Party customer;
  @override
  ConsumerState<CustomerLedgerCard> createState() => _CustomerLedgerCardState();
}

class _CustomerLedgerCardState extends ConsumerState<CustomerLedgerCard> {
  DayRange _range = DayRange.thisMonth();

  Future<void> _openInvoice(int id) async {
    try {
      final inv = await ref.read(salesRepoProvider).getDelivery(id);
      if (mounted) await showInvoiceShareSheet(context, inv);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(ledgerProvider((widget.customer.id, _range)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Account ledger', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
          const SizedBox(height: 4),
          Text(_range.label, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          data.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(ledgerProvider)),
            data: (lg) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _row('Opening balance', '', '', lg.opening, bold: true),
              const Divider(height: 1),
              if (lg.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Is period mein koi transaction nahi.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                ),
              for (final e in lg.entries) ...[
                InkWell(
                  onTap: e.kind == 'delivery' ? () => _openInvoice(e.refId) : null,
                  child: _row(
                    '${formatDate(e.date)} · ${e.refNo}\n${e.description}',
                    e.kind == 'delivery' ? e.debit : '',
                    e.kind == 'payment' ? e.credit : '',
                    e.balance,
                    icon: e.kind == 'delivery' ? Icons.receipt_long : Icons.payments_outlined,
                  ),
                ),
                const Divider(height: 1),
              ],
              _row('Total (${lg.totalBirds} birds, ${formatKg(lg.totalWeight)})', lg.totalDebit, lg.totalCredit, '', bold: true),
              const Divider(height: 1),
              _row('Closing balance', '', '', lg.closing, bold: true),
              const SizedBox(height: 6),
              const Text('Invoice par tap karein → WhatsApp / SMS / PDF',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(String label, String bill, String paid, String balance, {bool bold = false, IconData? icon}) {
    final w = bold ? FontWeight.w700 : FontWeight.w400;
    String m(String v) => v.isEmpty ? '' : formatMoney(v);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[Icon(icon, size: 18, color: AppColors.textMuted), const SizedBox(width: 8)],
        Expanded(flex: 4, child: Text(label, style: TextStyle(fontWeight: w))),
        Expanded(flex: 2, child: Text(m(bill), textAlign: TextAlign.right, style: TextStyle(fontWeight: w))),
        Expanded(
            flex: 2,
            child: Text(m(paid), textAlign: TextAlign.right, style: TextStyle(fontWeight: w, color: AppColors.paid))),
        Expanded(
          flex: 2,
          child: Text(m(balance),
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: w, color: isPositiveAmount(balance) ? AppColors.due : AppColors.text)),
        ),
      ]),
    );
  }
}
