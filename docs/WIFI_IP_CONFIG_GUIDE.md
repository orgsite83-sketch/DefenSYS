# Wi-Fi / IP Address Change Guide for DefenSYS

This guide explains how to update the system configuration when your computer connects to a different Wi-Fi network or your local IPv4 address changes (e.g. to `192.168.1.10`).

---

## 1. Check Your Current Local IP Address

On Windows PowerShell:
```powershell
ipconfig
```
Look for **IPv4 Address** under your active Wi-Fi / Ethernet adapter (for example: `192.168.1.10`).

---

## 2. Backend Configuration (Django API Server)

### A. Run Server on All Network Interfaces
When hosting the server on a local network, start Django using `0.0.0.0:8000` so it accepts connections from other devices:
```powershell
cd backend
python manage.py runserver 0.0.0.0:8000
```

### B. Update Allowed Hosts File
If Django blocks incoming requests from your new IP address, update your environment settings or configuration files:

1. **Primary Config File:** [backend/.env](file:///c:/Users/Admin/Desktop/DefenSYS/backend/.env) (or create from [.env.example](file:///c:/Users/Admin/Desktop/DefenSYS/backend/.env.example))
   ```env
   DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,192.168.1.10,10.0.2.2
   ```

2. **Backend Settings Code:** [settings.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/defensys_backend/settings.py#L58-L61)
   > [!NOTE]
   > During local development (`DEBUG=True`), DefenSYS automatically allows `192.168.*` and `10.*` LAN IPs for CORS.

---

## 3. Frontend API Host Configuration (Flutter Mobile & Web)

You can configure the frontend API host using **command-line arguments** (recommended) or by **editing the source code**.

### Option A: Using Command Line Flags (No Code Edits Required)

#### 1. Mobile (Physical Android / iOS device on the same Wi-Fi):
Pass your PC's Wi-Fi IP address using `--dart-define`:
```powershell
cd frontend
flutter run --dart-define=DEFENSYS_API_HOST=192.168.1.10
```

#### 2. Android Emulator (Host PC loopback):
```powershell
cd frontend
flutter run --dart-define=DEFENSYS_ANDROID_EMULATOR=true
```

#### 3. Web (Chrome / Flutter Web):
- **Development with Fixed Web Port & Chrome popup:**
  ```powershell
  cd frontend
  flutter run -d chrome --web-port=57583 --dart-define=DEFENSYS_API_HOST=192.168.1.236
  ```

- **Web Server Mode (No Chrome Popup & Accessible via LAN IP):**
  *Use `-d web-server` and `--web-hostname=0.0.0.0` so it doesn't open popups and allows accessing via IP in as many browser tabs as you want:*
  ```powershell
  cd frontend
  flutter run -d web-server --web-hostname=0.0.0.0 --web-port=57583 --dart-define=DEFENSYS_API_HOST=192.168.1.236
  ```

- **Building Web for Production / Distribution:**
  ```powershell
  cd frontend
  flutter build web --dart-define=DEFENSYS_API_HOST=192.168.1.236
  ```

---

### Option B: Editing the Source Code File (Changing Defaults)

If you prefer to permanently set a new default LAN IP in the codebase without using `--dart-define` every time:

* **File to Edit:** [api_config.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/config/api_config.dart#L19)
* **Lines to Update:**
  ```dart
  // Line 19 in frontend/lib/config/api_config.dart
  static const String fallbackLanIp = '192.168.1.10';

  // Line 16 in frontend/lib/config/api_config.dart
  static const List<String> serverIps = ['192.168.1.10', '127.0.0.1'];
  ```

---

## Quick Reference Summary

| Target | Command / Action | Configuration File / Parameter |
|---|---|---|
| **Find IP** | `ipconfig` (Windows) | Look for IPv4 Address |
| **Backend Server** | `python manage.py runserver 0.0.0.0:8000` | [backend/.env](file:///c:/Users/Admin/Desktop/DefenSYS/backend/.env) (`DJANGO_ALLOWED_HOSTS`) |
| **Mobile App (Wi-Fi)** | `flutter run --dart-define=DEFENSYS_API_HOST=192.168.1.10` | CLI argument (or edit [api_config.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/config/api_config.dart#L19)) |
| **Web App (Dev)** | `flutter run -d chrome --web-port=57583 --dart-define=DEFENSYS_API_HOST=192.168.1.236` | CLI argument (pins port 57583) |
| **Web App (Build)** | `flutter build web --dart-define=DEFENSYS_API_HOST=192.168.1.10` | CLI build argument |
