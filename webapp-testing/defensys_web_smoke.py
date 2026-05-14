"""
Smoke test: Django API reachable + Flutter web login shell loads.

Run via with_server (from repo root or webapp-testing), for example:

  cd webapp-testing
  python scripts/with_server.py --timeout 600 ^
    --server "cd /d C:\\path\\to\\DefensyS\\backend && python manage.py runserver 0.0.0.0:8000" --port 8000 ^
    --server "cd /d C:\\path\\to\\DefensyS\\frontend && flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080" --port 8080 ^
    -- python defensys_web_smoke.py
"""
from __future__ import annotations

import os
import sys

from playwright.sync_api import sync_playwright

WEB = os.environ.get("DEFENSYS_WEB_URL", "http://127.0.0.1:8080/")
API = os.environ.get("DEFENSYS_API_CHECK_URL", "http://127.0.0.1:8000/admin/login/")


def main() -> int:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        try:
            ctx = browser.new_context()
            resp = ctx.request.get(API)
            if not resp.ok:
                print(f"FAIL: API check {API} -> HTTP {resp.status}", file=sys.stderr)
                return 1
            print(f"OK: API check {API} -> HTTP {resp.status}")

            page = ctx.new_page()
            page.goto(WEB.rstrip("/") + "/", wait_until="domcontentloaded", timeout=180_000)
            # Dev server keeps WS open; networkidle may never settle — load is enough.
            page.wait_for_load_state("load", timeout=180_000)

            candidates: list[tuple[str, object]] = [
                ("a11y Sign In button", page.get_by_role("button", name="Sign In")),
                ("flutter-view", page.locator("flutter-view").first),
                ("flt-scene-host", page.locator("flt-scene-host").first),
                ("flt-glass-pane", page.locator("flt-glass-pane").first),
                ("canvas", page.locator("canvas").first),
            ]
            last_err: Exception | None = None
            for label, loc in candidates:
                try:
                    loc.wait_for(state="attached", timeout=60_000)
                    print(f"OK: {label} (attached)")
                    break
                except Exception as e:
                    last_err = e
                    continue
            else:
                dump = os.path.join(
                    os.path.dirname(__file__), "..", ".tmp", "smoke_fail.html"
                )
                os.makedirs(os.path.dirname(dump), exist_ok=True)
                with open(dump, "w", encoding="utf-8") as f:
                    f.write(page.content())
                shot = dump.replace(".html", ".png")
                page.screenshot(path=shot, full_page=True)
                print(f"FAIL: no Flutter shell matched. Wrote {dump} and {shot}", file=sys.stderr)
                if last_err:
                    print(last_err, file=sys.stderr)
                return 1
            print(f"OK: Flutter web loaded at {WEB}")
        finally:
            browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
