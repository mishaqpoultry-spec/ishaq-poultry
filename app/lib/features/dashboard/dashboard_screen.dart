import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/decimal_math.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/date_range_bar.dart';
import '../auth/auth_controller.dart';
import '../parties/party.dart';
import '../sales/invoice_share_sheet.dart';
import '../sales/sales.dart';
import '../sales/supplies_screen.dart';
import '../sales/supply_form.dart';

/// Total outstanding across all customers (sum of server-computed balances).
final _outstandingProvider = FutureProvider.autoDispose<({String total, int customers})>((ref) async {
  final page = await ref.watch(partyRepoProvider).list(PartyKind.customer, pageSize: 500);
  var sum = Dec.zero();
  var owing = 0;
  for (final c in page.items) {
    final b = Dec.tryParse(c.currentBalance ?? c.openingBalance, scale: 2) ?? Dec.zero();
    if (!b.isNegative && !b.isZero) owing++;
    sum = sum + b;
  }
  return (total: sum.toString(), customers: owing);
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final today = DayRange.today();
    final todayData = ref.watch(deliveryListProvider((range: today, customerId: null, includeCancelled: false)));
    final outstanding = ref.watch(_outstandingProvider);
    final t = Theme.of(context).textTheme;

    Future<void> newSupply() async {
      final inv = await showSupplyForm(context);
      if (inv == null || !context.mounted) return;
      refreshAfterInvoiceChange(ref);
      ref.invalidate(_outstandingProvider);
      await showInvoiceShareSheet(context, inv, justCreated: true);
    }

    String? total(String key) => todayData.value?.totals[key]?.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(deliveryListProvider);
          ref.invalidate(_outstandingProvider);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          // --- Hero ---------------------------------------------------------
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: softShadow,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                  style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 6),
              Text('Assalam-o-Alaikum, ${user?.fullName ?? ''}', style: t.headlineSmall?.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text('M Ishaq Poultry Services', style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.greenDark),
                onPressed: newSupply,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('New Supply / Invoice'),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text("Today's summary", style: t.titleMedium),
          const SizedBox(height: 12),
          // Cards size to their content (no fixed aspect ratio -> no overflow on small phones).
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 900 ? 4 : 2;
            const gap = 12.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            final cards = <Widget>[
              _StatCard(
                icon: Icons.receipt_long,
                label: 'Invoices',
                value: todayData.isLoading ? null : '${total('count') ?? 0}',
                sub: todayData.isLoading ? null : formatKg(total('net_weight')),
                onTap: () => context.go('/supplies'),
              ),
              _StatCard(
                icon: Icons.trending_up,
                label: 'Sales',
                value: todayData.isLoading ? null : formatMoney(total('total_amount')),
                onTap: () => context.go('/supplies'),
              ),
              _StatCard(
                icon: Icons.payments_outlined,
                label: 'Received',
                value: todayData.isLoading ? null : formatMoney(total('payment_received')),
                valueColor: AppColors.paid,
                onTap: () => context.go('/supplies'),
              ),
              _StatCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Total outstanding',
                value: outstanding.isLoading ? null : formatMoney(outstanding.value?.total),
                sub: outstanding.value == null ? null : '${outstanding.value!.customers} customers',
                valueColor: AppColors.due,
                onTap: () => context.go('/customers'),
              ),
            ];
            return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: w, child: card)]);
          }),
          if (todayData.hasError || outstanding.hasError) ...[
            const SizedBox(height: 12),
            Text('${todayData.error ?? outstanding.error}', style: t.bodySmall?.copyWith(color: AppColors.due)),
          ],
          const SizedBox(height: 22),
          Text('Quick actions', style: t.titleMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _QuickAction(icon: Icons.storefront_outlined, label: 'Customers', onTap: () => context.go('/customers')),
            _QuickAction(icon: Icons.receipt_long_outlined, label: 'All invoices', onTap: () => context.go('/supplies')),
            _QuickAction(icon: Icons.sell_outlined, label: 'Rates', onTap: () => context.go('/rates')),
          ]),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, this.sub, this.valueColor, this.onTap});
  final IconData icon;
  final String label;
  final String? value; // null = loading
  final String? sub;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.green, size: 20),
            ),
            const SizedBox(height: 12),
            Text(label, style: t.bodySmall?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            if (value == null)
              const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value!,
                    style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, color: valueColor, fontFeatures: tabularFigures)),
              ),
            if (sub != null) Text(sub!, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: AppColors.green),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
