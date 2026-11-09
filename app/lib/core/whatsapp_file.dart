import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('shahzad_poultry/whatsapp');

enum WhatsAppFileResult { opened, notInstalled, unsupported, failed }

/// Android only: opens WhatsApp directly in [internationalPhone]'s chat with
/// the file at [path] attached and [caption] as text. The user presses Send.
/// [path] must be inside the app cache dir (getTemporaryDirectory()).
Future<WhatsAppFileResult> sendFileToWhatsAppChat({
  required String path,
  required String internationalPhone,
  String caption = '',
}) async {
  if (!Platform.isAndroid) return WhatsAppFileResult.unsupported;
  try {
    final r = await _channel.invokeMethod<String>(
      'sendFile',
      {'path': path, 'phone': internationalPhone, 'text': caption},
    );
    return switch (r) {
      'opened' => WhatsAppFileResult.opened,
      'not_installed' => WhatsAppFileResult.notInstalled,
      _ => WhatsAppFileResult.failed,
    };
  } on PlatformException {
    return WhatsAppFileResult.failed;
  } on MissingPluginException {
    return WhatsAppFileResult.unsupported;
  }
}
