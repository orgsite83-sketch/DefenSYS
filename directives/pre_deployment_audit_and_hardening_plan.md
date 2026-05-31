# Pre-Deployment Audit & Hardening Plan

This document details the critical audit findings, deployment blockers, and security vulnerabilities identified before the system updates can be pushed to the online server, along with the precise step-by-step code changes required to resolve them.

---

## 1. Audit Findings Summary

| # | Severity | Component | Finding | Direct Impact | Status |
|---|----------|-----------|---------|---------------|--------|
| 1 | 🔴 Critical | Frontend | String literal `!` in Bearer header | Causes API calls to fail and forces auto-logout during token refresh retries. | **Action Required** |
| 2 | 🔴 Critical | Backend | Missing `STATIC_ROOT` in `settings.py` | Deployment crash: `python manage.py collectstatic` will fail on the server. | **Action Required** |
| 3 | 🔴 Critical | Backend | Untracked migration files in git | Database schema mismatch: migrations will not run on the online server. | **Action Required** |
| 4 | 🔴 Critical | Security | No rate limiting on login endpoint | Susceptible to credential stuffing and brute force attacks. | **Action Required** |
| 5 | 🔴 Critical | Security | Guest code validate endpoint leaks internal data | Unauthenticated endpoint exposes internal IDs, guest names, and team details. | **Action Required** |
| 6 | 🟠 High | Security | WebSockets have no origin validation | Vulnerable to cross-site WebSockets hijacking. | **Action Required** |
| 7 | 🟠 High | Security | Incomplete path traversal check in media view | Encoded paths could bypass `..` check and read files outside `MEDIA_ROOT`. | **Action Required** |
| 8 | 🟡 Medium | Security | Guest validate endpoint is enumerable | Lack of throttling allows attackers to easily brute-force guest codes. | **Action Required** |

---

## 2. Pre-Deployment Action Plan

Follow these steps to apply all required updates before pushing to the online server.

### Step 1: Fix Frontend Bearer Token String Literal Bug
* **File:** [authenticated_client.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/services/authenticated_client.dart#L214)
* **Action:** Remove the literal `!` from the authentication header.
* **Diff:**
```diff
-   request.headers['Authorization'] = 'Bearer $token!';
+   request.headers['Authorization'] = 'Bearer $token';
```

---

### Step 2: Configure `STATIC_ROOT` for Deployment
* **File:** [settings.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/defensys_backend/settings.py)
* **Action:** Define the `STATIC_ROOT` setting so Django can collect static files.
* **Diff:**
```diff
  # Static files (CSS, JavaScript, Images)
  # https://docs.djangoproject.com/en/6.0/howto/static-files/
  
  STATIC_URL = 'static/'
+ STATIC_ROOT = BASE_DIR / 'staticfiles'
```

---

### Step 3: Enable Rate Limiting & Throttling
* **File 1:** [settings.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/defensys_backend/settings.py#L255)
* **Action:** Define the default throttling rates for authentication and public endpoints.
* **Diff:**
```diff
      'EXCEPTION_HANDLER': 'defensys_backend.exception_handlers.defensys_exception_handler',
      'DEFAULT_THROTTLE_RATES': {
          'token_refresh': '10/min',
+         'login': '5/min',
+         'anon': '10/min',
      },
```

* **File 2:** [views.py (authentication_access_control)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/authentication_access_control/views.py#L26)
* **Action:** Add the custom login rate throttle and apply it to the Token View.
* **Diff:**
```diff
+ from rest_framework.throttling import AnonRateThrottle
...
+ class LoginRateThrottle(AnonRateThrottle):
+     scope = 'login'
+ 
  class CustomTokenObtainPairView(TokenObtainPairView):
      serializer_class = CustomTokenObtainPairSerializer
      permission_classes = [AllowAny]
+     throttle_classes = [LoginRateThrottle]
```

* **File 3:** [views.py (user_management)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/views.py#L339)
* **Action:** Throttle the public guest validation endpoint using the default anonymous throttle rate.
* **Diff:**
```diff
+ from rest_framework.throttling import AnonRateThrottle
...
  class GuestCodeValidateView(APIView):
      """Public endpoint to validate guest panelist codes"""
      permission_classes = [AllowAny]
+     throttle_classes = [AnonRateThrottle]
```

---

### Step 4: Add WebSockets Origin Validation
* **File:** [asgi.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/defensys_backend/asgi.py)
* **Action:** Wrap the router inside `AllowedHostsOriginValidator`.
* **Diff:**
```diff
+ from channels.security.websocket import AllowedHostsOriginValidator
  
  application = ProtocolTypeRouter({
      'http': django_asgi_app,
-     'websocket': URLRouter(websocket_urlpatterns),
+     'websocket': AllowedHostsOriginValidator(
+         URLRouter(websocket_urlpatterns)
+     ),
  })
```

---

### Step 5: Harden Path Traversal Checks on Media Server
* **File:** [media_views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/defensys_backend/media_views.py#L19)
* **Action:** Use `os.path.normpath` and check for absolute path escapes.
* **Diff:**
```diff
+ import os
...
      def get(self, request, file_path):
          if getattr(settings, 'USE_S3', False):
              raise Http404('Media is served from object storage.')
  
-         if not file_path or '..' in file_path:
-             raise Http404('Invalid file path.')
+         resolved = os.path.normpath(file_path)
+         if '..' in resolved or resolved.startswith('/') or resolved.startswith('\\'):
+             raise Http404('Invalid file path.')
```

---

### Step 6: Track and Commit Migration Files
* **Action:** Stage and commit the three database migrations left untracked:
  ```bash
  git add backend/modules/defense/migrations/0010_stagedeliverable_vault_file_template.py
  git add backend/modules/defense/migrations/0011_piteventgradingconfig_vault_file_template.py
  git add backend/modules/grading/migrations/0008_alter_teamgrade_status.py
  ```

---

## 3. Post-Fix Verification

Run the following checks to ensure everything builds and passes:
1. Run backend tests:
   ```bash
   python manage.py test
   ```
2. Verify Django production readiness:
   ```bash
   python manage.py check --deploy
   ```
3. Build the Flutter web project release:
   ```powershell
   cd frontend
   flutter build web --release
   ```
