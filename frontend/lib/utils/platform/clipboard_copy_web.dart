import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> copyTextToClipboard(String text) async {
  if (text.isEmpty) {
    return false;
  }
  // LAN HTTP pages do not expose navigator.clipboard. Copy synchronously in
  // the original click handler instead of awaiting an API that cannot work.
  if (!web.window.isSecureContext) return _copyTextWithSelection(text);
  try {
    await web.window.navigator.clipboard.writeText(text).toDart;
    return true;
  } catch (_) {
    return _copyTextWithSelection(text);
  }
}

/// Compatibility path for browsers without the secure Clipboard API.
/// The temporary selection is removed and keyboard focus is restored even if
/// copying is denied. Keep the selectable UI available as a manual fallback.
bool _copyTextWithSelection(String text) {
  if (text.isEmpty || web.document.body == null) return false;
  final previousFocus = web.document.activeElement;
  final field = web.HTMLTextAreaElement()
    ..value = text
    ..readOnly = true
    ..tabIndex = -1;
  field.style
    ..position = 'fixed'
    ..left = '-9999px'
    ..top = '0'
    ..opacity = '0';
  web.document.body!.appendChild(field);
  try {
    field.focus();
    field.select();
    field.setSelectionRange(0, text.length);
    return web.document.execCommand('copy');
  } catch (_) {
    return false;
  } finally {
    field.remove();
    if (previousFocus != null && previousFocus.isA<web.HTMLElement>()) {
      (previousFocus as web.HTMLElement).focus();
    }
  }
}
