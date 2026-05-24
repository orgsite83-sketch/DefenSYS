import 'package:flutter/services.dart';

Future<bool> copyTextToClipboard(String text) async {
  if (text.isEmpty) {
    return false;
  }
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}
