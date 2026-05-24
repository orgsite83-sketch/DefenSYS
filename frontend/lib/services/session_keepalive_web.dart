import 'dart:html' as html;

void onBrowserTabVisible(void Function() callback) {
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      callback();
    }
  });
}
