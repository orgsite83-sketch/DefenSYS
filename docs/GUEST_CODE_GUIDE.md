# Guest Code System — How It Works

This guide explains the guest panelist code system end-to-end: what it is, how it's generated, how it's validated, and how the web prototype and Flutter app connect through it.

---

## What Is a Guest Code?

A guest code is a temporary access token that lets an **external panelist** (someone without a DefenSYS account) join a specific defense evaluation session. Instead of creating a full user account, the admin generates a short code like `DEF-A3X9KZ` and hands it to the guest. The guest enters it in the Flutter app to get limited panelist access for that one defense.

Guest access is:
- **Tied to one specific defense schedule** — the code only works for the defense it was generated for
- **Time-limited** — expires 4 hours after creation
- **Revocable** — admin can invalidate it at any time from the User Management screen

---

## The Full Flow

```
Admin (Web Prototype)                    Guest Panelist (Flutter App)
─────────────────────                    ────────────────────────────
1. Opens User Management
2. Clicks "Generate Guest Code"
3. Enters guest name + selects defense
4. Clicks "Generate & Save"
   → Code created: DEF-A3X9KZ
   → Saved to localStorage
   → Saved to MockDB.guestTokens
   → POSTed to /api/guest-codes
                                         5. Opens Flutter app
                                         6. Taps "Guest Panelist Access"
                                         7. Enters: DEF-A3X9KZ
                                         8. App calls GET /api/guest-code/DEF-A3X9KZ
                                         9. Server validates → returns defense info
                                        10. App navigates to PanelistDashboard
                                        11. Guest can grade the assigned defense
```

---

## Step 1 — Admin Generates the Code (Web)

**Where:** User Management page → "Generate Guest Code" button

The modal asks for:
- **Guest Panelist Name** — e.g. "Engr. Juan Dela Cruz" (display name only, no account needed)
- **Defense Schedule** — dropdown of all `status: 'scheduled'` entries from `MockDB.schedules`

On clicking "Generate & Save":

```js
// 1. Generate a random 6-char alphanumeric code
const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
let randomPart = '';
for (let i = 0; i < 6; i++) randomPart += chars.charAt(Math.floor(Math.random() * chars.length));
const code = `DEF-${randomPart}`;  // e.g. DEF-A3X9KZ

// 2. Build the entry object
const guestEntry = {
  guestName: 'Engr. Juan Dela Cruz',
  code: 'DEF-A3X9KZ',
  defenseId: 'sched-1776738971921-team-team-vaultsync',
  isActive: true,
  createdAt: new Date().toISOString(),
  expiresAt: Date.now() + (4 * 60 * 60 * 1000)  // 4 hours from now
};
```

---

## Step 2 — Where the Code Gets Saved (3 places)

### Place 1: localStorage (web prototype persistence)

```js
const stored = JSON.parse(localStorage.getItem('guestCodes') || '[]');
stored.push(guestEntry);
localStorage.setItem('guestCodes', JSON.stringify(stored));
```

`localStorage` survives page reloads and browser restarts. This is what the Guest Codes management table reads from. It is **not** cleared by `sessionStorage.clear()` — only by `resetDemo()` which explicitly calls `localStorage.removeItem('guestCodes')`.

### Place 2: MockDB.guestTokens (in-memory + sessionStorage)

```js
MockDB.guestTokens.push({
  token: code,           // 'DEF-A3X9KZ'
  evalId: defenseId,     // schedule ID
  expiresAt: guestEntry.expiresAt
});
MockDB._save();
```

This is what `rbac.js` reads when validating a guest token via URL params (web-side validation). The key difference from `guestCodes` in localStorage: this uses `token` not `code`, and `evalId` not `defenseId`.

### Place 3: mock_database.json (server persistence)

```js
fetch('http://localhost:8080/api/guest-codes', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(guestEntry)
});
```

The mock server appends the entry to `mock_database.json`. This is what the **Flutter app** reads when validating the code — it calls `GET /api/guest-code/DEF-A3X9KZ` and the server looks it up from the JSON file.

---

## Step 3 — Flutter App Validates the Code

In `login_screen.dart`, the guest dialog calls:

```dart
final guestData = await BridgeService.validateGuestCode(code);
```

`BridgeService.validateGuestCode` hits:

```
GET http://localhost:8080/api/guest-code/DEF-A3X9KZ
```

The mock server (`mock_server.py`) handles this:

```python
elif parsed_url.path.startswith("/api/guest-code/"):
    code = parsed_url.path.split("/")[-1]
    db = read_db()
    guest = next(
        (g for g in db.get("guestCodes", [])
         if g.get("code") == code and g.get("isActive")),
        None
    )
    if guest:
        # Returns the full guestEntry object
        self.wfile.write(json.dumps(guest).encode("utf-8"))
    else:
        # 404 — invalid or revoked
```

If valid, the Flutter app gets back:
```json
{
  "guestName": "Engr. Juan Dela Cruz",
  "code": "DEF-A3X9KZ",
  "defenseId": "sched-1776738971921-team-team-vaultsync",
  "isActive": true,
  "createdAt": "2026-04-21T10:37:00.000Z",
  "expiresAt": 1745234220000
}
```

The app then navigates to `PanelistDashboard` with:
```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => PanelistDashboard(
      userData: {
        'name': guestData['guestName'],
        'id': code,
        'role': 'guest_panelist',
        'defenseId': guestData['defenseId'],
      },
    ),
  ),
);
```

---

## Step 4 — Web-Side Guest Validation (URL Token)

There's a second validation path for the web prototype — a guest can also access the live evaluation board directly via a URL with query params:

```
/templates/evaluation_engine/live_evaluation_board.html?guest_token=DEF-A3X9KZ&eval=sched-...
```

`rbac.js` handles this in `_validateGuestToken()`:

```js
function _validateGuestToken() {
  const params = new URLSearchParams(window.location.search);
  const token  = params.get('guest_token');  // 'DEF-A3X9KZ'
  const evalId = params.get('eval');          // schedule ID

  // Validate against MockDB.guestTokens
  const stored = (MockDB.guestTokens || []).find(
    t => t.token === token && t.evalId === evalId && Date.now() < t.expiresAt
  );

  if (!stored) return false;

  // Write a temporary GUEST session
  sessionStorage.setItem(RBAC_SESSION_KEY, JSON.stringify({
    userId: `guest-${token.slice(0, 6)}`,
    name: 'Guest Panelist',
    baseRole: 'guest',
    roles: ['GUEST', 'PANELIST'],
    evalId: evalId,
    expiresAt: stored.expiresAt,
  }));
  return true;
}
```

This is called by `enforcePageClearance(['PANELIST'], { allowGuest: true })` on the evaluation board page.

---

## Step 5 — Revoking a Code

From the Guest Codes table in User Management, clicking "Revoke":

```js
// 1. Mark as inactive in localStorage
codes[idx].isActive = false;
localStorage.setItem('guestCodes', JSON.stringify(codes));

// 2. Sync revocation to the server
fetch('http://localhost:8080/api/guest-codes/revoke', {
  method: 'POST',
  body: JSON.stringify({ code: 'DEF-A3X9KZ' })
});
```

The server sets `isActive: false` in `mock_database.json`. Any subsequent `GET /api/guest-code/DEF-A3X9KZ` will return 404 because the server filters by `isActive: true`.

---

## Data Structure Reference

### localStorage `guestCodes` array
```js
[
  {
    guestName: 'Engr. Juan Dela Cruz',
    code: 'DEF-A3X9KZ',
    defenseId: 'sched-1776738971921-team-team-vaultsync',
    isActive: true,
    createdAt: '2026-04-21T10:37:00.000Z',
    expiresAt: 1745234220000   // Unix ms timestamp
  }
]
```

### MockDB.guestTokens array (different shape — used by rbac.js)
```js
[
  {
    token: 'DEF-A3X9KZ',      // same as code
    evalId: 'sched-...',       // same as defenseId
    expiresAt: 1745234220000
  }
]
```

### MockDB.guestCodes (seed data in mock-data.js)
```js
[
  {
    guestName: 'Demo Guest',
    code: 'DEF-DEMO01',
    defenseId: 'sched-001',
    isActive: true,
    createdAt: '2026-04-12T08:00:00.000Z',
    expiresAt: 9999999999999   // never expires — demo only
  }
]
```

---

## Storage Locations Summary

| Storage | Key | Used by | Cleared by |
|---|---|---|---|
| `localStorage` | `guestCodes` | Guest Codes table (web) | `resetDemo()` only |
| `sessionStorage` (MockDB) | `guestTokens` | `rbac.js` URL validation | Page reload / `resetDemo()` |
| `mock_database.json` | `guestCodes` | Flutter app, mock server | `/api/reset` endpoint |

---

## Common Issues

**Code works in Flutter but not on web (URL token path)**
The URL token path reads from `MockDB.guestTokens` (sessionStorage). If the page was reloaded after generating the code, `MockDB.guestTokens` is empty because it's not in the seed data. The fix: the code is also in `localStorage.guestCodes` — but `rbac.js` doesn't read localStorage, it reads MockDB. For the demo, use the Flutter app path instead of the URL token path.

**Code not found in Flutter app**
The Flutter app reads from `mock_database.json` via the server. If the server wasn't running when the code was generated, the POST to `/api/guest-codes` failed silently. The code exists in localStorage but not in the JSON file. Fix: restart the server and regenerate the code.

**Code expired**
Codes expire 4 hours after creation. The `expiresAt` field is a Unix millisecond timestamp. The demo seed code `DEF-DEMO01` has `expiresAt: 9999999999999` so it never expires.

**Revoked code still works in Flutter**
Revocation POSTs to the server but the Flutter app caches nothing — it always hits the server fresh. If the server is offline, revocation only updates localStorage and the server JSON won't be updated until the server comes back online.
