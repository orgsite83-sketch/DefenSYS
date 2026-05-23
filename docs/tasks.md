# Implementation Plan & Tasks: Python Bridge (Web to Flutter)

## How the Logic Connects
Your existing logic (like `rbac.js` protecting pages, and `mock-data.js` managing team data) is absolutely going to stay! We are NOT throwing away your hard work. 

**Here is how it connects:**
Right now, `rbac.js` looks at `sessionStorage` to decide if someone is an Admin or a PIT Lead. We will keep that exactly the same! The only thing that changes is *where* that data comes from when they first log in. Instead of loading from your hardcoded `mock-data.js` array, it will run a quick `fetch()` to `mock_server.py`, get the role, and then hand it right back to `rbac.js` to do its magic. Because Flutter also asks `mock_server.py`, both apps share the EXACT same logic truth.

---

## Task Checklist for Implementation

- [x] **Step 1: Extract `mock_database.json`**
  - Create `prototype/mock_database.json`.
  - Copy the `users: [...]` array out of `mock-data.js` so it becomes the universal source of truth for both Web and Mobile.

- [x] **Step 2: Build `mock_server.py`**
  - Write the python script in the `prototype/` folder.
  - Implement static file serving (replacing `python -m http.server`).
  - Add API Route: `GET /api/users/<id>` (For Flutter to read the role).
  - Add API Route: `POST /api/assign-role` (For the Web Admin to save a role).

- [x] **Step 3: Modify the Web UI (`prototype/js/`)**
  - Update the "Assign Role" button's javascript. Instead of updating a local array, it sends a `fetch("http://localhost:8080/api/assign-role", { method: 'POST', ... })` request.
  - Update the Login screen to `fetch` the user profile from the server, then pass that profile directly into your existing `setRBACSession(user)` function in `rbac.js`.

- [x] **Step 4: Update the Flutter UI (`user/lib/`)**
  - Import the `http` package in `pubspec.yaml`.
  - In `main.dart` (or the login screen), add the API call to `http://localhost:8080/api/users/<id>`.
  - If the returned JSON says `role: "PANELIST"`, push the Navigator to the Panelist UI screen. If it says `role: "STUDENT"`, push to the Student UI screen.
