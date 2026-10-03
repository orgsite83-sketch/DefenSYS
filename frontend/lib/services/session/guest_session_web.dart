import 'package:web/web.dart' as web;

const _key = 'defensys.guest.evaluation';
const _mode = 'defensys.guest.portal';
bool isGuestPortalSession() {
  try {
    return web.window.sessionStorage.getItem(_mode) == '1';
  } catch (_) {
    return false;
  }
}

void exitGuestPortalMode() {
  try {
    web.window.sessionStorage.removeItem(_mode);
  } catch (_) {
    /* Storage may be disabled. */
  }
}

bool isGuestPortalLocation() =>
    Uri.base.path.startsWith('/guest/') ||
    Uri.base.fragment.startsWith('/guest/');
String? readGuestSession() {
  try {
    return web.window.sessionStorage.getItem(_key);
  } catch (_) {
    return null;
  }
}

void writeGuestSession(String value) {
  try {
    web.window.sessionStorage.setItem(_key, value);
    web.window.sessionStorage.setItem(_mode, '1');
  } catch (_) {
    /* Memory session still works. */
  }
}

void clearGuestSession() {
  try {
    web.window.sessionStorage.removeItem(_key);
  } catch (_) {
    /* Storage may be disabled. */
  }
}
