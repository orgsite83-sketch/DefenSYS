# Local DOCX layout preview

The web universal file viewer renders `.docx` bytes using docx-preview in a
sandboxed frame. Original bytes still drive downloads. Other platforms retain
the shared text/table preview. Failed layout rendering falls back to that view.

No document is uploaded to an external viewer. Libraries are bundled here, not
loaded from a CDN. The frame has scripts enabled but no same-origin permission,
and CSP blocks remote media, connections, embedded frames, and forms. Packaged
HTML (`altChunk`) is disabled. The parent/frame bridge checks the sending window
and a per-view channel. Document hyperlinks cannot navigate the frame.

The Dart bridge compares native WindowProxy identities using JS interop.
`dart:html` wraps cross-origin window getters in fresh Dart objects, so comparing
`MessageEvent.source` with `iframe.contentWindow` through those getters rejects
legitimate renderer messages. Keep both the native source check and channel check.

The renderer preserves document fonts, paragraph/run styles, images, headers,
footers, tables, page dimensions, explicit/saved page breaks, and tab stops where
supported. Fonts must be installed or embedded. Browser layout, complex drawing
objects, fields, and automatic pagination can differ from Word; this is not a
print-exact renderer. Paper remains in its original colors in dark mode.

`layout.js` corrects page-relative floating image offsets and keeps headers in
the margin area. It measures natural font line spacing and paginates single-column
block flow when saved page breaks are absent, repeating headers/footers and
keeping short table labels with their tables. Multiple columns, multiple section
articles, and footnote layouts retain the library's flow. Oversized indivisible
blocks can grow their page to preserve all content.

## Browser verification

From the repository root (Chrome installed; override `CHROME_PATH` if needed):

```powershell
npm install --prefix .tmp/docx-qa --ignore-scripts --no-audit --no-fund playwright-core@1.58.2
node frontend/test/browser/docx_layout_preview.cjs
```

Optionally pass the path to the original weekly accomplishment report template
as the final argument to verify that report and capture desktop/phone PNGs under
`.tmp/docx-layout-preview/`. The test server binds only to loopback and closes
afterward. Checks cover original styling, images, repeated headers/footers,
explicit and automatic pagination, merged tables, responsive fit, zoom, blocked
packaged HTML/navigation, no external document requests, and malformed input.

## Bundled dependencies

| Package | Version | Source | License |
| --- | --- | --- | --- |
| docx-preview | 0.4.1 | https://github.com/VolodymyrBaydalka/docxjs | Apache-2.0 |
| JSZip | 3.10.2 | https://github.com/Stuk/jszip | MIT or GPL-3.0-or-later (used under MIT) |

License texts are retained in `vendor/`. Distribution files were extracted from
the exact npm tarballs after verifying their published SHA-512 integrity:

```
docx-preview-0.4.1.tgz
sha512-Dv4g+LeE0swHpPvNC0lAT0YsR5Zq5pAxw7d3vHQ8EChBLgIrqqe9VPL5nVt2HBJap8bEZbXUI0TJob7kBeNU9w==

jszip-3.10.2.tgz
sha512-3l+rb15IOWtUhU0H5MFqES/T6Kh7abYwjosBey/vD6hDt8zoEffkSC5Ws5SGtgVw3gBx2NEbhTeSW1+kWkpyTQ==
```

Only update these pinned files deliberately and rerun the DOCX browser checks.
