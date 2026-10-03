String? _session;
bool _guestPortal = false;
bool isGuestPortalLocation() => false;
bool isGuestPortalSession() => _guestPortal;
void exitGuestPortalMode() => _guestPortal = false;
String? readGuestSession() => _session;
void writeGuestSession(String value) {
  _session = value;
  _guestPortal = true;
}

void clearGuestSession() => _session = null;
