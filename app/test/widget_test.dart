import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shahzad_poultry/core/api_client.dart';
import 'package:shahzad_poultry/core/contact_launcher.dart';
import 'package:shahzad_poultry/core/decimal_math.dart';
import 'package:shahzad_poultry/widgets/date_range_bar.dart';
import 'package:shahzad_poultry/core/format.dart';
import 'package:shahzad_poultry/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('money formatting keeps decimals and handles null', () {
    expect(formatMoney('15000.5'), 'Rs 15,000.50');
    expect(formatMoney(null), 'Rs 0.00');
    expect(isPositiveAmount('0.00'), isFalse);
    expect(isPositiveAmount('10'), isTrue);
  });

  test('exact decimal maths matches server rounding', () {
    final amount = (Dec.tryParse('480.00', scale: 2)! * Dec.tryParse('1030.250')!).round(2);
    expect(amount.toString(), '494520.00');
    // Half-up rounding: 0.333 kg x 1.50 = 0.4995 -> 0.50
    expect((Dec.tryParse('1.50', scale: 2)! * Dec.tryParse('0.333')!).round(2).toString(), '0.50');
    final total = amount + Dec.tryParse('3000', scale: 2)! + Dec.tryParse('500', scale: 2)!;
    expect(total.toString(), '498020.00');
    expect(Dec.tryParse('1.2345'), isNull); // more than 3 decimals
    expect(Dec.tryParse('abc'), isNull);
    expect((Dec.tryParse('100')! - Dec.tryParse('70.5')!).toString(), '29.500');
  });

  test('server URL normalisation', () {
    expect(normalizeServerUrl('192.168.100.7:8000'), 'http://192.168.100.7:8000');
    expect(normalizeServerUrl(' http://192.168.100.7:8000/ '), 'http://192.168.100.7:8000');
    expect(normalizeServerUrl('http://192.168.100.7:8000/health'), 'http://192.168.100.7:8000');
    expect(normalizeServerUrl('HTTP://10.0.2.2:8000/docs'), 'HTTP://10.0.2.2:8000');
  });

  test('date range presets', () {
    final week = DayRange.thisWeek();
    expect(week.from.weekday, DateTime.monday);
    expect(DayRange.today().isSingleDay, isTrue);
    expect(DayRange.lastDays(7).days, 7);
    final lm = DayRange.lastMonth();
    expect(lm.from.day, 1);
    expect(lm.to.add(const Duration(days: 1)).day, 1); // last day of month
  });

  test('WhatsApp number normalisation for Pakistani formats', () {
    expect(toInternational('0300-6388084'), '923006388084');
    expect(toInternational('0300 638 8084'), '923006388084');
    expect(toInternational('+92 300 6388084'), '923006388084');
    expect(toInternational('923006388084'), '923006388084');
    expect(toInternational('00923006388084'), '923006388084');
    expect(toInternational('3006388084'), '923006388084');
    expect(toInternational('0300-63880'), isNull); // too short
    expect(toInternational('abc'), isNull);
    expect(toInternational(null), isNull);
    expect(toInternational('+971501234567'), '971501234567'); // foreign with +
  });

  testWidgets('shows login screen when no saved token', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const ShahzadPoultryApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('M Ishaq Poultry Services'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });
}
