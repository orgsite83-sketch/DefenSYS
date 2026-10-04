@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;
import 'package:defensys/utils/clipboard_copy.dart';

@JS('Object.defineProperty')
external JSObject _defineProperty(
  JSObject object,
  JSString name,
  JSObject descriptor,
);
@JS('Object.getOwnPropertyDescriptor')
external JSObject? _descriptor(JSObject object, JSString name);

bool _deniedCopy(String _) => throw StateError('Copy denied');

void _override(JSObject object, String name, JSAny? value) {
  final original = _descriptor(object, name.toJS);
  _defineProperty(
    object,
    name.toJS,
    <String, Object?>{'value': value, 'configurable': true}.jsify() as JSObject,
  );
  addTearDown(() {
    if (original == null) {
      object.delete(name.toJS);
    } else {
      _defineProperty(object, name.toJS, original);
    }
  });
}

void main() {
  setUp(() => _override(web.window, 'isSecureContext', false.toJS));

  test(
    'LAN HTTP copies the complete selection synchronously and restores focus',
    () async {
      final originalField = web.HTMLInputElement()..value = 'Keep my draft';
      web.document.body!.appendChild(originalField);
      addTearDown(() => originalField.remove());
      originalField.focus();
      const value =
          'DEF-123456\nhttp://192.168.1.3/#/guest/evaluate?code=DEF-123456';
      String? selection;
      final textareasBefore = web.document.querySelectorAll('textarea').length;
      _override(
        web.document,
        'execCommand',
        ((String command) {
          expect(command, 'copy');
          final field = web.document.activeElement as web.HTMLTextAreaElement;
          selection = field.value.substring(
            field.selectionStart,
            field.selectionEnd,
          );
          return true;
        }).toJS,
      );
      final result = copyTextToClipboard(value);
      expect(
        selection,
        value,
        reason: 'Copy must run before the click handler yields.',
      );
      expect(await result, isTrue);
      expect(web.document.querySelectorAll('textarea').length, textareasBefore);
      expect(web.document.activeElement, originalField);
      expect(originalField.value, 'Keep my draft');
    },
  );

  test(
    'a denied browser copy reports failure and removes the temporary field',
    () async {
      final before = web.document.querySelectorAll('textarea').length;
      _override(web.document, 'execCommand', ((String _) => false).toJS);
      expect(await copyTextToClipboard('DEF-123456'), isFalse);
      expect(web.document.querySelectorAll('textarea').length, before);
    },
  );

  test(
    'browser exceptions still clean up and restore the original focus',
    () async {
      final originalField = web.HTMLInputElement();
      web.document.body!.appendChild(originalField);
      addTearDown(() => originalField.remove());
      originalField.focus();
      final before = web.document.querySelectorAll('textarea').length;
      _override(web.document, 'execCommand', _deniedCopy.toJS);
      expect(await copyTextToClipboard('DEF-123456'), isFalse);
      expect(web.document.querySelectorAll('textarea').length, before);
      expect(web.document.activeElement, originalField);
    },
  );

  test('empty content never writes to the clipboard', () async {
    var writes = 0;
    _override(
      web.document,
      'execCommand',
      ((String _) {
        writes++;
        return true;
      }).toJS,
    );
    expect(await copyTextToClipboard(''), isFalse);
    expect(writes, 0);
  });
}
