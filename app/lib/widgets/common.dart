import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/format.dart';
import '../core/theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/logo.svg', width: size, height: size);
}

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: compact ? 32 : 44),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('M Ishaq Poultry',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: compact ? 15 : 18, color: AppColors.text)),
              if (!compact)
                const Text('Services', style: TextStyle(color: AppColors.green, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.due),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined, this.action});
  final String message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Amount coloured by meaning: outstanding (red) or received/paid (green).
class AmountText extends StatelessWidget {
  const AmountText(this.value, {super.key, this.kind = AmountKind.neutral, this.bold = false});
  final String? value;
  final AmountKind kind;
  final bool bold;
  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      AmountKind.due => isPositiveAmount(value) ? AppColors.due : AppColors.text,
      AmountKind.paid => AppColors.paid,
      AmountKind.neutral => AppColors.text,
    };
    return Text(formatMoney(value),
        style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontFeatures: tabularFigures));
  }
}

enum AmountKind { neutral, due, paid }

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final active = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: active ? AppColors.greenSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(active ? 'Active' : 'Inactive',
          style: TextStyle(fontSize: 12, color: active ? AppColors.green : AppColors.textMuted)),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.due : null,
    behavior: SnackBarBehavior.floating,
  ));
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirm'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
