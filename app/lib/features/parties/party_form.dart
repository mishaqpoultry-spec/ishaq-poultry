import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contact_launcher.dart';
import '../../widgets/common.dart';
import 'party.dart';

final _phoneRe = RegExp(r'^[0-9+\-\s]{7,20}$');
final _amountRe = RegExp(r'^-?\d{1,12}(\.\d{1,2})?$');

/// Opens the add/edit form. Returns the saved party, or null if cancelled.
Future<Party?> showPartyForm(BuildContext context, PartyKind kind, {Party? existing}) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final form = _PartyForm(kind: kind, existing: existing);
  return showDialog<Party>(
    context: context,
    barrierDismissible: false,
    builder: (_) => wide
        ? Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: form))
        : Dialog.fullscreen(child: form),
  );
}

class _PartyForm extends ConsumerStatefulWidget {
  const _PartyForm({required this.kind, this.existing});
  final PartyKind kind;
  final Party? existing;
  @override
  ConsumerState<_PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends ConsumerState<_PartyForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _secondary = TextEditingController(text: widget.existing?.secondaryName);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _whatsapp = TextEditingController(text: widget.existing?.whatsapp);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _opening = TextEditingController(text: widget.existing?.openingBalance ?? '0');
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late String _type = widget.existing?.customerType ?? 'shop';
  late String _status = widget.existing?.status ?? 'active';
  bool _busy = false;

  bool get _isCustomer => widget.kind == PartyKind.customer;
  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _secondary, _phone, _whatsapp, _address, _opening, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _optPhone(String? v) =>
      (v == null || v.trim().isEmpty || _phoneRe.hasMatch(v.trim())) ? null : 'Enter a valid number';

  /// WhatsApp must be a real mobile number so the chat button can open it.
  String? _waPhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return toInternational(v) == null ? 'Enter mobile number like 0300-1234567 or +923001234567' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      _isCustomer ? 'business_name' : 'farm_name': _secondary.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'notes': _notes.text.trim(),
      if (_isCustomer) 'whatsapp': _whatsapp.text.trim(),
      if (_isCustomer) 'customer_type': _type,
      if (_isEdit) 'status': _status,
      if (!_isEdit) 'opening_balance': _opening.text.trim().isEmpty ? '0' : _opening.text.trim(),
    };
    setState(() => _busy = true);
    try {
      final repo = ref.read(partyRepoProvider);
      final saved = _isEdit
          ? await repo.update(widget.kind, widget.existing!.id, body)
          : await repo.create(widget.kind, body);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    const gap = SizedBox(height: 14);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit ${k.singular}' : 'New ${k.singular}'),
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
          TextFormField(
            controller: _name,
            autofocus: !_isEdit,
            decoration: InputDecoration(labelText: '${k.singular} name *'),
            maxLength: 120,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          TextFormField(
            controller: _secondary,
            decoration: InputDecoration(labelText: k.secondaryLabel),
            maxLength: 160,
          ),
          if (_isCustomer) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Customer type'),
              items: [for (final e in customerTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _type = v ?? 'shop'),
            ),
            gap,
          ],
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Contact number', hintText: '0300-1234567'),
                keyboardType: TextInputType.phone,
                validator: _optPhone,
              ),
            ),
            if (_isCustomer) ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _whatsapp,
                  decoration: InputDecoration(
                    labelText: 'WhatsApp number',
                    hintText: '0300-1234567',
                    suffixIcon: IconButton(
                      tooltip: 'Same as contact',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () => _whatsapp.text = _phone.text,
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: _waPhone,
                ),
              ),
            ],
          ]),
          gap,
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
            maxLines: 2,
            maxLength: 500,
          ),
          if (!_isEdit) ...[
            TextFormField(
              controller: _opening,
              decoration: InputDecoration(
                labelText: 'Opening balance (Rs)',
                helperText: _isCustomer
                    ? 'Amount this customer already owes you. Cannot be edited later.'
                    : 'Amount you already owe this supplier. Cannot be edited later.',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
              validator: (v) =>
                  (v == null || v.trim().isEmpty || _amountRe.hasMatch(v.trim())) ? null : 'Enter a valid amount (max 2 decimals)',
            ),
            gap,
          ],
          if (_isEdit) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Account status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
            gap,
          ],
          TextFormField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
            maxLength: 2000,
          ),
        ]),
        ),
      ),
    );
  }
}
