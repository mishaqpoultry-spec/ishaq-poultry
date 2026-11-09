import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/contact_launcher.dart';
import '../../core/decimal_math.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_file.dart';
import '../../widgets/common.dart';
import 'sales.dart';

/// Bottom sheet shown after "Generate Invoice" (and when tapping any invoice):
/// short summary + WhatsApp / SMS. Each opens THAT customer's chat with a neat
/// invoice message already written — the user presses Send.
Future<void> showInvoiceShareSheet(BuildContext context, Invoice inv, {bool justCreated = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _InvoiceSheet(inv: inv, justCreated: justCreated),
  );
}

class _InvoiceSheet extends ConsumerStatefulWidget {
  const _InvoiceSheet({required this.inv, required this.justCreated});
  final Invoice inv;
  final bool justCreated;
  @override
  ConsumerState<_InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends ConsumerState<_InvoiceSheet> {
  String? _busy; // 'wa' or 'sms'

  Invoice get inv => widget.inv;

  Future<File> _savePdf() async {
    final bytes = await ref.read(salesRepoProvider).invoicePdf(inv.id);
    final dir = await getTemporaryDirectory(); // app cache dir (shared via FileProvider)
    final f = File('${dir.path}${Platform.pathSeparator}${inv.invoiceNo}.pdf');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// WhatsApp: opens THIS customer's chat with the invoice PDF attached
  /// (Android). If the direct route isn't available, opens the share menu with
  /// the PDF. On Windows (no WhatsApp file intent) it opens the chat with text.
  Future<void> _whatsAppPdf() async {
    setState(() => _busy = 'wa');
    try {
      final m = await ref.read(salesRepoProvider).message(inv.id);
      final number = toInternational(m.whatsapp);
      if (number == null) {
        _snack('${inv.customerName}: WhatsApp number not saved. Add it from Customer → Edit.', error: true);
        return;
      }
      if (!Platform.isAndroid) {
        if (!await openWhatsApp(number, message: m.text)) _snack('Could not open WhatsApp.', error: true);
        return;
      }
      final f = await _savePdf();
      final caption = 'Invoice ${inv.invoiceNo} — ${inv.customerName}';
      final r = await sendFileToWhatsAppChat(path: f.path, internationalPhone: number, caption: caption);
      switch (r) {
        case WhatsAppFileResult.opened:
          break; // WhatsApp is open on the customer's chat with the PDF; user presses Send.
        case WhatsAppFileResult.notInstalled:
          _snack('WhatsApp is not installed on this phone.', error: true);
        case WhatsAppFileResult.unsupported:
        case WhatsAppFileResult.failed:
          await SharePlus.instance.share(
              ShareParams(files: [XFile(f.path, mimeType: 'application/pdf')], text: caption));
      }
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _send({required bool whatsapp}) async {
    setState(() => _busy = whatsapp ? 'wa' : 'sms');
    try {
      final m = await ref.read(salesRepoProvider).message(inv.id);
      final number = whatsapp ? m.whatsapp : m.phone;
      if (toInternational(number) == null) {
        _snack('${inv.customerName}: ${whatsapp ? 'WhatsApp' : 'phone'} number not saved. Add it from Customer → Edit.',
            error: true);
        return;
      }
      final ok = whatsapp ? await openWhatsApp(number!, message: m.text) : await openSms(number!, message: m.smsText);
      if (!ok) _snack('Could not open ${whatsapp ? 'WhatsApp' : 'SMS app'} on this device.', error: true);
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (mounted) showSnack(context, m, error: error);
  }

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: bold ? AppColors.text : AppColors.textMuted))),
            Text(value, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
    final hasDiscount = isPositiveAmount(inv.discount);
    final totalPayable = _add(inv.previousBalance, inv.total);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.justCreated)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.check_circle, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(child: Text('Invoice ${inv.invoiceNo} saved')),
              ]),
            ),
          Text(inv.customerName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            '${inv.invoiceNo} · ${formatDate(inv.date)}${inv.time != null ? ', ${inv.time}' : ''}'
            '${inv.cancelled ? ' · CANCELLED' : ''}',
            style: TextStyle(color: inv.cancelled ? AppColors.due : AppColors.textMuted),
          ),
          const Divider(height: 24),
          line('Live Chicken${inv.birds > 0 ? ' — ${inv.birds} pieces' : ''}', ''),
          line('${formatKg(inv.netWeight)} × Rs ${inv.rate}/KG', formatMoney(inv.amount)),
          if (hasDiscount) line('Discount (Rs ${inv.discountPerKg}/KG)', '− ${formatMoney(inv.discount)}', color: AppColors.due),
          line('Amount after discount', formatMoney(inv.total), bold: true),
          line('Previous balance', formatMoney(inv.previousBalance),
              color: isPositiveAmount(inv.previousBalance) ? AppColors.due : null),
          line('Total payable', formatMoney(totalPayable), bold: true),
          line('Payment received', formatMoney(inv.paymentReceived), color: AppColors.paid),
          const Divider(height: 16),
          line('Remaining balance', formatMoney(inv.balanceAfter),
              bold: true, color: isPositiveAmount(inv.balanceAfter) ? AppColors.due : AppColors.paid),
          const SizedBox(height: 18),
          const Text('Send invoice', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _button('wa', 'WhatsApp (PDF)', Icons.picture_as_pdf, const Color(0xFF25D366), _whatsAppPdf)),
            const SizedBox(width: 10),
            Expanded(child: _button('sms', 'SMS', Icons.sms_outlined, AppColors.green, () => _send(whatsapp: false))),
          ]),
          const SizedBox(height: 10),
          const Text(
            "WhatsApp: opens the customer's chat with the invoice PDF attached.\n"
            'SMS: opens the SMS app with the invoice message written. Just press Send.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ]),
      ),
    );
  }

  Widget _button(String id, String label, IconData icon, Color color, VoidCallback onTap) {
    if (_busy == id) {
      return const SizedBox(height: 52, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(52)),
      onPressed: _busy == null ? onTap : null,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 16)),
    );
  }

  /// Exact sum of two decimal strings for display (server stores the real figures).
  static String _add(String a, String b) =>
      ((Dec.tryParse(a, scale: 2) ?? Dec.zero()) + (Dec.tryParse(b, scale: 2) ?? Dec.zero())).toString();
}
