import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/auth_controller.dart';
import 'party.dart';
import 'party_form.dart';

class PartyListScreen extends ConsumerStatefulWidget {
  const PartyListScreen({super.key, required this.kind});
  final PartyKind kind;
  @override
  ConsumerState<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends ConsumerState<PartyListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String? _status = 'active';

  PartyQuery get _query => (kind: widget.kind, q: _q, status: _status);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _q = v.trim()));
  }

  Future<void> _add() async {
    final saved = await showPartyForm(context, widget.kind);
    if (saved != null && mounted) {
      ref.invalidate(partyListProvider);
      showSnack(context, '${widget.kind.singular} ${saved.code} saved');
    }
  }

  void _open(Party p) => context.go('${widget.kind.endpoint}/${p.id}');

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    final canManage = ref.watch(currentUserProvider)?.canManage ?? false;
    final data = ref.watch(partyListProvider(_query));
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(title: Text(k.plural)),
      floatingActionButton: canManage && !wide
          ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: Text('Add ${k.singular}'))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: wide ? 360 : double.infinity,
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search name, ${k.secondaryLabel.toLowerCase()}, code or phone',
                  isDense: true,
                ),
              ),
            ),
            SegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: 'active', label: Text('Active')),
                ButtonSegment(value: 'inactive', label: Text('Inactive')),
                ButtonSegment(value: null, label: Text('All')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            if (canManage && wide)
              FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: Text('Add ${k.singular}')),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: data.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(partyListProvider(_query))),
            data: (page) {
              if (page.items.isEmpty) {
                return EmptyView(
                  icon: k == PartyKind.customer ? Icons.storefront_outlined : Icons.agriculture_outlined,
                  message: _q.isEmpty ? 'No ${k.plural.toLowerCase()} yet.' : 'No match for "$_q".',
                  action: canManage && _q.isEmpty
                      ? FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: Text('Add ${k.singular}'))
                      : null,
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.refresh(partyListProvider(_query).future),
                child: wide ? _table(page.items) : _list(page.items),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _list(List<Party> items) => ListView.separated(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, i) {
          final p = items[i];
          return ListTile(
            onTap: () => _open(p),
            leading: CircleAvatar(
              backgroundColor: AppColors.greenSoft,
              child: Text(p.name.characters.first.toUpperCase(), style: const TextStyle(color: AppColors.green)),
            ),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([p.code, if (p.secondaryName != null) p.secondaryName!, if (p.phone != null) p.phone!].join(' · ')),
            trailing: AmountText(p.currentBalance ?? p.openingBalance, kind: AmountKind.due),
          );
        },
      );

  Widget _table(List<Party> items) {
    final k = widget.kind;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: const WidgetStatePropertyAll(AppColors.surface),
            columns: [
              const DataColumn(label: Text('Code')),
              const DataColumn(label: Text('Name')),
              DataColumn(label: Text(k.secondaryLabel)),
              if (k == PartyKind.customer) const DataColumn(label: Text('Type')),
              const DataColumn(label: Text('Phone')),
              DataColumn(label: Text(k.balanceLabel), numeric: true),
              const DataColumn(label: Text('Status')),
            ],
            rows: [
              for (final p in items)
                DataRow(onSelectChanged: (_) => _open(p), cells: [
                  DataCell(Text(p.code)),
                  DataCell(Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(p.secondaryName ?? '-')),
                  if (k == PartyKind.customer) DataCell(Text(customerTypes[p.customerType] ?? '-')),
                  DataCell(Text(p.phone ?? '-')),
                  DataCell(AmountText(p.currentBalance ?? p.openingBalance, kind: AmountKind.due)),
                  DataCell(StatusChip(p.status)),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
