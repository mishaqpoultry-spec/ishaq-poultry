import 'package:url_launcher/url_launcher.dart';

/// Converts a Pakistani number in any common format to international digits
/// (no plus sign), e.g. "0300-1234567", "+92 300 1234567", "3001234567" ->
/// "923001234567". Returns null if it does not look like a valid number.
String? toInternational(String? raw) {
  if (raw == null) return null;
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('0092')) d = d.substring(2);
  if (d.startsWith('03') && d.length == 11) d = '92${d.substring(1)}';
  if (d.startsWith('3') && d.length == 10) d = '92$d';
  // Pakistani mobile: 92 + 10 digits. Other countries: accept 10-15 digits
  // when the user typed them with a country code.
  if (d.startsWith('92')) return d.length == 12 ? d : null;
  return (raw.trim().startsWith('+') && d.length >= 10 && d.length <= 15) ? d : null;
}

/// Opens the customer's WhatsApp chat with an optional prefilled message.
/// This only opens the chat; it does NOT send anything or attach files.
Future<bool> openWhatsApp(String number, {String message = ''}) {
  final n = toInternational(number);
  if (n == null) return Future.value(false);
  final uri = Uri.https('wa.me', '/$n', message.isEmpty ? null : {'text': message});
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens the SMS app on the customer's number with an optional message.
Future<bool> openSms(String number, {String message = ''}) {
  final n = toInternational(number);
  if (n == null) return Future.value(false);
  final uri = Uri(scheme: 'sms', path: '+$n', queryParameters: message.isEmpty ? null : {'body': message});
  return launchUrl(uri);
}

Future<bool> openDialer(String number) {
  final n = toInternational(number);
  if (n == null) return Future.value(false);
  return launchUrl(Uri(scheme: 'tel', path: '+$n'));
}
