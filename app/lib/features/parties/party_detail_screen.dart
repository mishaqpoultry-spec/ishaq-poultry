import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contact_launcher.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/auth_controller.dart';
import '../sales/customer_ledger_card.dart';
import 'party.dart';
import 'party_form.dart';

class PartyDetailScreen extends ConsumerWidget {
  const PartyDetailScreen({super.key, required this.kind, required this.id});
  final PartyKind kind;
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(partyDetailProvider((kind, id)));
    final canManage = ref.watch(currentUserProvider)?.canManage ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(data.value?.name ?? kind.singular),
        actions: [
          if (canManage && data.hasValue)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                onPressed: () async {
                  final saved = await showPartyForm(context, kind, existing: data.value);
                  if (saved != null) {
                    ref.invalidate(partyDetailProvider((kind, id)));
                    ref.invalidate(partyListProvider);
                    if (context.mounted) showSnack(context, 'Saved');
                  }
                },
              ),
            ),
        ],
      ),
      body: data.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(partyDetailProvider((kind, id)))),
        data: (p) => ListView(padding: const EdgeInsets.all(16), children: [
          _Header(p),
          const SizedBox(height: 12),
          _ContactActions(p),
          if (kind == PartyKind.customer) ...[
            const SizedBox(height: 10),
            CustomerSalesActions(p),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final info = _InfoCard(p);
            final balance = _BalanceCard(p);
            if (c.maxWidth < 760) return Column(children: [balance, const SizedBox(height: 16), info]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: info),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: balance),
            ]);
          }),
          const SizedBox(height: 16),
          if (kind == PartyKind.customer) CustomerLedgerCard(p),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.p);
  final Party p;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.greenSoft,
        child: Text(p.name.characters.first.toUpperCase(),
            style: const TextStyle(fontSize: 22, color: AppColors.green, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text([p.code, if (p.secondaryName != null) p.secondaryName!].join(' · '),
              style: const TextStyle(color: AppColors.textMuted)),
        ]),
      ),
      StatusChip(p.status),
    ]);
  }
}

/// WhatsApp / SMS / Call buttons that open the saved number directly.
class _ContactActions extends StatelessWidget {
  const _ContactActions(this.p);
  final Party p;

  Future<void> _run(BuildContext context, Future<bool> Function() action, String app) async {
    bool ok;
    try {
      ok = await action();
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) showSnack(context, 'Could not open $app on this device.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final wa = p.kind == PartyKind.customer ? (p.whatsapp ?? p.phone) : p.phone;
    final waOk = toInternational(wa) != null;
    final phoneOk = toInternational(p.phone) != null;
    const missing = 'Number not saved. Use Edit to add it.';

    return Wrap(spacing: 10, runSpacing: 10, children: [
      Tooltip(
        message: waOk ? 'Open WhatsApp chat with ${p.name}' : missing,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
          onPressed: waOk ? () => _run(context, () => openWhatsApp(wa!), 'WhatsApp') : null,
          icon: const Icon(Icons.chat),
          label: const Text('WhatsApp'),
        ),
      ),
      Tooltip(
        message: phoneOk ? 'Send SMS to ${p.phone}' : missing,
        child: OutlinedButton.icon(
          onPressed: phoneOk ? () => _run(context, () => openSms(p.phone!), 'SMS') : null,
          icon: const Icon(Icons.sms_outlined),
          label: const Text('SMS'),
        ),
      ),
      Tooltip(
        message: phoneOk ? 'Call ${p.phone}' : missing,
        child: OutlinedButton.icon(
          onPressed: phoneOk ? () => _run(context, () => openDialer(p.phone!), 'dialer') : null,
          icon: const Icon(Icons.call_outlined),
          label: const Text('Call'),
        ),
      ),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(this.p);
  final Party p;
  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, String? value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
            Expanded(child: SelectableText(value == null || value.isEmpty ? '-' : value)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (p.kind == PartyKind.customer) row(Icons.category_outlined, 'Type', customerTypes[p.customerType]),
          row(Icons.phone_outlined, 'Contact', p.phone),
          if (p.kind == PartyKind.customer) row(Icons.chat_outlined, 'WhatsApp', p.whatsapp),
          row(Icons.place_outlined, 'Address', p.address),
          row(Icons.event_outlined, 'Added on', formatDate(p.createdAt)),
          row(Icons.notes_outlined, 'Notes', p.notes),
        ]),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard(this.p);
  final Party p;
  @override
  Widget build(BuildContext context) {
    final current = p.currentBalance ?? p.openingBalance;
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p.kind.balanceLabel} balance', style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          DefaultTextStyle.merge(style: const TextStyle(fontSize: 26), child: AmountText(current, kind: AmountKind.due, bold: true)),
          const Divider(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Opening balance', style: TextStyle(color: AppColors.textMuted)),
            AmountText(p.openingBalance),
          ]),
        ]),
      ),
    );
  }
}
