# DefenSYS System Audit

> Full-stack security & code quality audit — **2026-05-28**
> Last audited commit: current `main` branch

---

## Findings Summary

| # | Severity | Category | Finding | File(s) |
|---|----------|----------|---------|---------|
| 1 | 🔴 Critical | Security | Bulk-imported user passwords = username | `user_management/views.py:237` |
| 2 | 🔴 Critical | Security | No rate limiting on login endpoint | `authentication_access_control/views.py:26-28` |
| 3 | 🔴 Critical | Security | Guest code validate endpoint leaks internal data | `user_management/views.py:339-363` |
| 4 | 🔴 Critical | Security | WebSocket has no origin validation | `defensys_backend/asgi.py:16-21` |
| 5 | 🟠 High | Production | Missing production security headers | `defensys_backend/settings.py` |
| 6 | 🟠 High | Production | `DEBUG` defaults to `True` | `defensys_backend/settings.py:51` |
| 7 | 🟠 High | Security | Path traversal check is incomplete in media view | `defensys_backend/media_views.py:19` |
| 8 | 🟠 High | Security | `db.sqlite3` checked into repo | `backend/` |
| 9 | 🟠 High | Frontend | WebSocket token passed in URL query string | `frontend/lib/config/api_config.dart:148-154` |
| 10 | 🟡 Medium | Security | Guest validate is enumerable (no throttle) | `user_management/views.py:339` |
| 11 | 🟡 Medium | Code Quality | Redundant `IsSystemAdmin` / `IsAdminRole` permissions | `user_management/permissions.py:9-28` |
| 12 | 🟡 Medium | Frontend | `_ensureReady` spins 200 times with no backoff | `frontend/lib/services/authenticated_client.dart:45-56` |
| 13 | 🟡 Medium | Frontend | Bug: `sendAuthenticated` sets `'Bearer $token!'` (literal `!`) | `frontend/lib/services/authenticated_client.dart:214` |
| 14 | 🟡 Medium | Code Quality | No default pagination on list endpoints | `authentication_access_control/views.py:52-68` |
| 15 | 🟡 Medium | Production | CORS middleware dev-only — no production CORS | `defensys_backend/cors.py` |
| 16 | 🟢 Low | Code Quality | `UserSerializer` exposes all flags to client | `authentication_access_control/serializers.py:21-31` |
| 17 | 🟢 Low | Code Quality | Vault loads ALL entries into memory | `repository/vault/services.py:126-129` |
| 18 | 🟢 Low | Frontend | JWT expiry uses local device time (clock skew risk) | `frontend/lib/services/jwt_utils.dart:30` |
| 19 | 🟢 Low | Production | `STATIC_ROOT` not set for `collectstatic` | `defensys_backend/settings.py:198` |

---

## 🔴 Critical Findings

### 1. Bulk-imported passwords = student ID number

**File:** `backend/modules/user_management/views.py:237`

```python
user = User.objects.create_user(
    username=username,
    password=username,  # ← password IS the student ID
    ...
)
```

**Risk:** Every bulk-imported student's password is their student ID number (publicly known). Any attacker who knows a student ID can log in.

**Fix:**
```python
import secrets

temp_password = secrets.token_urlsafe(12)
user = User.objects.create_user(
    username=username,
    password=temp_password,
    ...
)
user.must_change_password = True  # Add BooleanField to User model
user.save(update_fields=['must_change_password'])
```

Alternatively, generate a random password and force password change on first login. At minimum, add a `force_password_change` flag and enforce it in the login serializer.

**Status:** `[ ] Not fixed`

---

### 2. No rate limiting on login endpoint

**File:** `backend/modules/authentication_access_control/views.py:26-28`

```python
class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer
    permission_classes = [AllowAny]
    # No throttle_classes!
```

**Risk:** Login endpoint has **no rate limiting**. Combined with #1 (predictable passwords), an attacker can brute-force accounts. Token refresh is throttled at 10/min, but login is wide open.

**Fix:**
```python
class LoginRateThrottle(AnonRateThrottle):
    scope = 'login'

class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer
    permission_classes = [AllowAny]
    throttle_classes = [LoginRateThrottle]
```

In `settings.py`:
```python
'DEFAULT_THROTTLE_RATES': {
    'token_refresh': '10/min',
    'login': '5/min',
}
```

**Status:** `[ ] Not fixed`

---

### 3. Guest code validate endpoint leaks internal data (unauthenticated)

**File:** `backend/modules/user_management/views.py:339-363`

```python
class GuestCodeValidateView(APIView):
    permission_classes = [AllowAny]  # Public!

    def get(self, request, code):
        # Returns: team ID, team name, defense stage, schedule ID, guest name
```

**Risk:** `AllowAny` endpoint returns **internal IDs** (team ID, schedule ID, guest name, defense stage) to anyone who guesses or brute-forces a guest code. Guest codes are short uppercase strings → easily enumerable.

**Fix:** Either:
- Remove this endpoint entirely (the `exchange` endpoint already validates)
- Add rate limiting + return minimal info (just `valid: true/false`)

**Status:** `[ ] Not fixed`

---

### 4. WebSocket has no origin validation

**File:** `backend/defensys_backend/asgi.py:16-21`

```python
application = ProtocolTypeRouter({
    'http': django_asgi_app,
    'websocket': URLRouter(websocket_urlpatterns),  # No AllowedHostsOriginValidator!
})
```

**Risk:** Any website can open a WebSocket to your server. While the consumer validates the JWT, a CSRF-style attack from a malicious page could use a stolen token.

**Fix:**
```python
from channels.security.websocket import AllowedHostsOriginValidator

application = ProtocolTypeRouter({
    'http': django_asgi_app,
    'websocket': AllowedHostsOriginValidator(
        URLRouter(websocket_urlpatterns),
    ),
})
```

**Status:** `[ ] Not fixed`

---

## 🟠 High Findings

### 5. Missing production security headers

**File:** `backend/defensys_backend/settings.py`

These Django security settings are **completely absent**:

| Setting | Purpose |
|---------|---------|
| `SECURE_SSL_REDIRECT` | Force HTTPS |
| `CSRF_COOKIE_SECURE` | CSRF cookie only over HTTPS |
| `SESSION_COOKIE_SECURE` | Session cookie only over HTTPS |
| `SECURE_HSTS_SECONDS` | HTTP Strict Transport Security |
| `SECURE_BROWSER_XSS_FILTER` | XSS protection header |
| `SECURE_CONTENT_TYPE_NOSNIFF` | Prevent MIME sniffing |

**Fix — add to `settings.py` (production only):**
```python
if not DEBUG:
    SECURE_SSL_REDIRECT = True
    CSRF_COOKIE_SECURE = True
    SESSION_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = 31536000  # 1 year
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = True
    SECURE_BROWSER_XSS_FILTER = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
```

**Status:** `[ ] Not fixed`

---

### 6. `DEBUG` defaults to `True`

**File:** `backend/defensys_backend/settings.py:51`

```python
DEBUG = _env_bool('DJANGO_DEBUG', default=True)
```

**Risk:** If the production `.env` is missing `DJANGO_DEBUG=False` (or `.env` isn't loaded), the server runs in debug mode — exposing full stack traces, SQL queries, and settings to users.

**Fix:** Change the default to `False`:
```python
DEBUG = _env_bool('DJANGO_DEBUG', default=False)
```

**Status:** `[ ] Not fixed`

---

### 7. Path traversal check is incomplete

**File:** `backend/defensys_backend/media_views.py:19`

```python
if not file_path or '..' in file_path:
    raise Http404('Invalid file path.')
```

**Risk:** Checking for `..` is partial. Encoded variants (`%2e%2e`), null bytes, symlink traversal aren't covered.

**Fix:**
```python
import os

resolved = os.path.normpath(file_path)
if '..' in resolved or resolved.startswith('/') or resolved.startswith('\\'):
    raise Http404('Invalid file path.')
```

**Status:** `[ ] Not fixed`

---

### 8. `db.sqlite3` exists in the repository

**File:** `backend/db.sqlite3` (483 KB)

While `.gitignore` lists `db.sqlite3`, the file still exists. If ever committed to git history, it could contain user data and hashed passwords.

**Fix:**
```bash
cd backend
git rm --cached db.sqlite3
```

Then verify it's not in git history with `git log --all -- db.sqlite3`.

**Status:** `[ ] Not fixed`

---

### 9. WebSocket JWT token passed in URL query string

**File:** `frontend/lib/config/api_config.dart:148-154`

```dart
static Uri webSocketGradingUri(String accessToken) {
    return Uri.parse(base).replace(
      queryParameters: {'token': accessToken},  // ← Token in URL
    );
}
```

**Risk:** Tokens in URLs appear in server access logs, browser history, proxy logs, and Nginx logs.

**Mitigation:**
- Configure Nginx to **not log** the `/ws/` query string
- Use a one-time ticket exchange: POST to get a short-lived WS ticket, connect with that
- Keep access token lifetime short for WS connections

**Status:** `[ ] Not mitigated`

---

## 🟡 Medium Findings

### 10. Guest validate is enumerable (no throttle)

`GuestCodeValidateView` is `AllowAny` with no rate limiting. Attacker can brute-force all guest codes.

**Fix:** Add `AnonRateThrottle` (e.g., 10/min). Consider making codes longer/more random.

**Status:** `[ ] Not fixed`

---

### 11. Duplicate permission classes

`IsSystemAdmin` and `IsAdminRole` in `user_management/permissions.py` are **identical**. Maintenance risk if one is updated but not the other.

**Fix:** Keep one, alias or delete the other.

**Status:** `[ ] Not fixed`

---

### 12. `_ensureReady` busy-spins 200 iterations

**File:** `frontend/lib/services/authenticated_client.dart:45-56`

```dart
while (auth.isRestoring && attempts < 200) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    // 200 × 25ms = 5 seconds of busy-polling
}
```

**Risk:** Wastes CPU/battery on mobile. Multiple concurrent API calls each spin independently.

**Fix:** Use a `Completer` that the auth bootstrap completes, so callers `await` a single future.

**Status:** `[ ] Not fixed`

---

### 13. Bug: String literal `!` in Bearer header

**File:** `frontend/lib/services/authenticated_client.dart:214`

```dart
request.headers['Authorization'] = 'Bearer $token!';
//  ← Inside a string, $token! sends literal "tokenvalue!" with trailing !
```

**Risk:** Appends a literal `!` to the token. Server rejects as invalid JWT. This path is hit on 401 retry in `sendAuthenticated`.

**Fix:**
```dart
request.headers['Authorization'] = 'Bearer ${token!}';
// Or just: 'Bearer $token' since null was checked above
```

**Status:** `[ ] Not fixed`

---

### 14. No default pagination on list endpoints

Most list endpoints (users, teams, schedules, vault entries) load **all records** in a single response with no pagination.

**Risk:** Performance degrades as the system grows.

**Fix:** Add `DEFAULT_PAGINATION_CLASS` to `REST_FRAMEWORK` settings.

**Status:** `[ ] Not fixed`

---

### 15. CORS middleware is dev-only

`cors.py` only adds CORS headers when `DEBUG=True`. In production, no CORS headers are sent. This works now (Nginx same-origin) but will break if cross-origin API access is needed.

**Status:** `[ ] Noted — acceptable for now`

---

## 🟢 Low Findings

### 16. `UserSerializer` exposes all flags to client

The `/me/` endpoint returns internal flags (`is_panelist`, `is_pit_lead`, `is_repo_assistant`, `is_uploader`). Not a vulnerability (used for UI routing) but best practice is to minimize data exposure.

**Status:** `[ ] Noted`

---

### 17. Vault loads ALL entries into memory

`repository/vault/services.py:126-129` fetches all entries into a Python list for filtering. Will degrade with hundreds/thousands of entries.

**Fix:** Move filtering to the database layer using Django ORM querysets.

**Status:** `[ ] Not fixed`

---

### 18. JWT expiry uses local device time

`jwt_utils.dart:30` uses `DateTime.now()` (local device clock). If a device clock is significantly off, tokens may be refreshed too aggressively or not at all.

**Mitigation:** The 90-second buffer helps. Consider using server time from response headers as reference.

**Status:** `[ ] Noted`

---

### 19. `STATIC_ROOT` not configured

`collectstatic` won't work without `STATIC_ROOT`. Admin panel CSS/JS won't serve in production.

**Fix:** Add to `settings.py`:
```python
STATIC_ROOT = BASE_DIR / 'staticfiles'
```

**Status:** `[ ] Not fixed`

---

## Recommended Priority

| Priority | Findings |
|----------|----------|
| **Immediate** | #1 (password), #2 (login throttle), #6 (DEBUG default) |
| **This week** | #3 (guest validate), #4 (WS origin), #5 (security headers), #7 (path traversal), #13 (bearer bug) |
| **Next sprint** | #8 (sqlite), #9 (WS token logging), #10 (guest throttle), #14 (pagination) |
| **Backlog** | #11, #12, #15, #16, #17, #18, #19 |

---

## Learnings & Updates

- When this audit is resolved, update this directive with the fix dates and any new patterns discovered.
- Re-run `python manage.py check --deploy` after applying fixes — it flags many of the production settings in #5.
- Re-audit after major feature additions or dependency upgrades.
