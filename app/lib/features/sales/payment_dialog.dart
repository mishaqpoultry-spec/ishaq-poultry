import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/decimal_math.dart';
import '../../core/format.dart';
import '../../widgets/common.dart';
import '../parties/party.dart';
import '../purchases/purchase.dart';
import 'sales.dart';

/// Payment without a new supply (customer clears old balance). Returns true if saved.
Future<bool> showPaymentDialog(BuildContext context, Party customer) async =>
    await showDialog<bool>(context: context, builder: (_) => _PaymentDialog(customer)) ?? false;

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog(this.customer);
  final Party customer;
  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  final _form = GlobalKey<FormState>();
  final _key = newIdempotencyKey();
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String _method = 'cash';
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(salesRepoProvider).addPayment({
        'idempotency_key': _key,
        'customer_id': widget.customer.id,
        'payment_date': DateFormat('yyyy-MM-dd').format(_date),
        'amount': _amount.text.trim(),
        'method': _method,
        'reference': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
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
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text('Payment — ${widget.customer.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Current baqaya: ${formatMoney(widget.customer.currentBalance ?? widget.customer.openingBalance)}'),
            gap,
            TextFormField(
              controller: _amount,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount (Rs) *'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              validator: (v) {
                final d = Dec.tryParse(v, scale: 2);
                return (d == null || d.isZero) ? 'Enter amount' : null;
              },
            ),
            gap,
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: [for (final e in paymentMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _method = v ?? 'cash'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (d != null) setState(() => _date = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date'),
                    child: Text(formatDate(_date)),
                  ),
                ),
              ),
            ]),
            gap,
            TextFormField(controller: _ref, decoration: const InputDecoration(labelText: 'Transaction ref. (optional)')),
            gap,
            TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save payment')),
      ],
    );
  }
}
