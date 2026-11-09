import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';

/// Inclusive date range (dates only, no time).
class DayRange {
  DayRange(DateTime from, DateTime to)
      : from = DateUtils.dateOnly(from),
        to = DateUtils.dateOnly(to);
  final DateTime from;
  final DateTime to;

  static DateTime get _today => DateUtils.dateOnly(DateTime.now());

  factory DayRange.today() => DayRange(_today, _today);
  factory DayRange.yesterday() {
    final y = _today.subtract(const Duration(days: 1));
    return DayRange(y, y);
  }
  factory DayRange.lastDays(int n) => DayRange(_today.subtract(Duration(days: n - 1)), _today);
  factory DayRange.thisWeek() {
    // Week starts Monday.
    final start = _today.subtract(Duration(days: _today.weekday - 1));
    return DayRange(start, _today);
  }
  factory DayRange.thisMonth() => DayRange(DateTime(_today.year, _today.month, 1), _today);
  factory DayRange.lastMonth() {
    final first = DateTime(_today.year, _today.month - 1, 1);
    return DayRange(first, DateTime(_today.year, _today.month, 0));
  }
  factory DayRange.thisYear() => DayRange(DateTime(_today.year, 1, 1), _today);

  bool get isSingleDay => from == to;
  int get days => to.difference(from).inDays + 1;

  String get apiFrom => _api.format(from);
  String get apiTo => _api.format(to);

  String get label {
    if (isSingleDay) return _nice.format(from);
    return '${_nice.format(from)} – ${_nice.format(to)}';
  }

  static final _api = DateFormat('yyyy-MM-dd');
  static final _nice = DateFormat('dd MMM yyyy');

  @override
  bool operator ==(Object other) => other is DayRange && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

/// Preset chips (Today, Yesterday, 7 days, Week, Month, Year) + custom picker.
class DateRangeBar extends StatelessWidget {
  const DateRangeBar({super.key, required this.value, required this.onChanged});
  final DayRange value;
  final ValueChanged<DayRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = <String, DayRange>{
      'Today': DayRange.today(),
      'Yesterday': DayRange.yesterday(),
      '7 days': DayRange.lastDays(7),
      'This week': DayRange.thisWeek(),
      'This month': DayRange.thisMonth(),
      'Last month': DayRange.lastMonth(),
      'This year': DayRange.thisYear(),
    };
    final isPreset = presets.containsValue(value);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in presets.entries) ...[
          ChoiceChip(
            label: Text(e.key),
            selected: value == e.value,
            selectedColor: AppColors.greenSoft,
            onSelected: (_) => onChanged(e.value),
          ),
          const SizedBox(width: 8),
        ],
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(isPreset ? 'Custom' : value.label),
          backgroundColor: isPreset ? null : AppColors.greenSoft,
          onPressed: () async {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              initialDateRange: DateTimeRange(start: value.from, end: value.to),
              helpText: 'Select any day or range',
            );
            if (r != null) onChanged(DayRange(r.start, r.end));
          },
        ),
      ]),
    );
  }
}
