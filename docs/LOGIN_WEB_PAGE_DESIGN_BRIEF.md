# DefenSYS Login Web Page Design Brief

## Goal

Improve the DefenSYS web login page so it feels more polished, modern, and school-system appropriate while staying clearly branded as DefenSYS.

The target direction is inspired by the reference login pages:

- A split desktop layout with a visual story area on the left and a focused login card on the right.
- Soft white or pale background instead of a heavy full-maroon top block.
- A strong brand lockup above the form.
- A clean login form with rounded inputs, subtle shadows, and simple supporting links.
- A motivational academic message paired with a campus/system collage.

This should be treated as inspiration, not a copy. DefenSYS should keep its own identity: capstone defense, PIT management, repositories, rubrics, faculty review, and academic records.

## Current DefenSYS Login

Current implementation: [`frontend/lib/screens/login_screen.dart`](../frontend/lib/screens/login_screen.dart)

The current web login already includes:

- Official DefenSYS logo from `assets/logo.png`.
- Username/email and password validation.
- Password visibility toggle.
- Remember-me option.
- Session-expired banner support.
- Loading state on submit.
- Web/mobile role routing rules.
- Mobile-only guest panelist access.

The redesign should preserve those behaviors and only change the presentation unless a separate functional change is requested.

## Reference Design Takeaways

### What Works In The References

| Reference trait | Why it works | DefenSYS adaptation |
|---|---|---|
| Split layout | Separates emotional branding from the task of signing in | Left: DefenSYS story panel. Right: login card |
| Hero collage | Makes the system feel tied to real campus life | Use defense panels, repository documents, rubrics, schedules, and PIT/team imagery |
| Compact login card | Keeps the login task focused | Keep form simple, not dashboard-like |
| Soft shadows | Adds depth without looking noisy | Use one elevated form card and one visual panel |
| Strong slogan | Gives personality | Use a DefenSYS-specific capstone/defense message |
| Pale background | Feels cleaner and more spacious | Use off-white, soft gray, and light maroon/gold accents |

### What To Avoid

- Do not copy the classmate's exact layout, logo style, wording, or collage.
- Do not use emoji-heavy decoration as the main identity.
- Do not make the login page look like a marketing landing page.
- Do not add long instructions on the screen.
- Do not remove security cues like password visibility, validation, and remember-me guidance.
- Do not use gold text on white for important labels because contrast is weak.

## Proposed Direction

### Concept Name

**DefenSYS Defense Desk**

The page should feel like a clean academic command desk: calm, official, and built for capstone defense work.

### Desktop Layout

Use a two-column layout for web screens at `>= 760px`.

| Area | Width | Content |
|---|---:|---|
| Left story panel | 55-60% | Brand lockup, collage/visual, headline, short supporting phrase |
| Right login panel | 40-45% | Login card centered vertically |

Suggested page structure:

```text
 ---------------------------------------------------------------
|                                                               |
|  [DefenSYS logo] DefenSYS                                     |
|  Capstone & PIT Management System                             |
|                                                               |
|       [visual collage / illustration panel]      [login card] |
|                                                               |
|  DEFEND WITH CLARITY.                         Welcome back     |
|  MANAGE WITH CONFIDENCE.                    [username input]  |
|                                             [password input]  |
|                                             [remember/forgot] |
|                                             [Log in button]   |
|                                                               |
 ---------------------------------------------------------------
```

### Mobile Layout

Keep the current mobile concept, but align it visually with the new web design:

- Logo and DefenSYS name at top.
- White rounded form area.
- Same improved input style.
- Keep guest panelist access on mobile only.
- Avoid forcing the left-side visual collage into narrow screens.

## Visual Identity

Use existing DefenSYS tokens from [`frontend/lib/theme/defensys_tokens.dart`](../frontend/lib/theme/defensys_tokens.dart).

| Token | Color | Use |
|---|---|---|
| `DefensysTokens.maroon` | `#7A110A` | Primary buttons, important accents, logo text |
| `DefensysTokens.maroonDark` | `#5E0D08` | Hover/pressed button state, deep accent |
| `DefensysTokens.gold` | `#D97706` | Small accent marks, selected items, decorative line |
| `DefensysTokens.background` | `#F3F4F6` | Page base |
| `DefensysTokens.surface` | `#FFFFFF` | Login card |
| `DefensysTokens.textPrimary` | `#111827` | Main text |
| `DefensysTokens.textSecondary` | `#6B7280` | Supporting text |

Suggested additional local colors for the page:

| Color | Use |
|---|---|
| `#F8FAFC` | Main background wash |
| `#FFF7ED` | Very light gold-tinted panel highlight |
| `#FDECEC` | Very light maroon-tinted accent area |
| `#E5E7EB` | Input border |

Keep the palette balanced. The page should not become all maroon, all beige, or all dark blue.

## Brand Lockup

Use the official D-shaped repository shield from `frontend/assets/logo.png`.

Recommended desktop lockup:

```text
[logo] DefenSYS
       Capstone & PIT Management System
```

Recommended login card header:

```text
Welcome back
Sign in to manage defenses, teams, and academic records.
```

Keep the full logo lockup in the left story panel, then use a smaller logo-only or wordmark version inside the card if needed.

## Hero Message Options

Pick one primary headline. The first option is recommended.

1. **Defend with clarity. Manage with confidence.**
2. **From proposal to final defense, keep every record in place.**
3. **One workspace for capstone defense readiness.**
4. **Organize teams, stages, rubrics, and defense records.**

Suggested supporting line:

```text
Track capstone teams, PIT progress, defense schedules, rubrics, grades, and repository submissions in one secure academic system.
```

## Visual Asset Direction

The left panel needs a real visual asset or carefully composed app-specific illustration. This is the biggest upgrade from the current page.

### Preferred Visual

Create a DefenSYS-specific collage image:

- Official DefenSYS logo or repository shield motif.
- Capstone students/team table.
- Faculty/panel defense scene.
- Repository folders/documents.
- Rubric or grade sheet preview.
- Calendar/schedule card.
- Small UI cards showing "Teams", "Defense", "Repository", and "Rubrics".

Recommended file path:

```text
frontend/assets/login_hero.png
```

Then register it in [`frontend/pubspec.yaml`](../frontend/pubspec.yaml):

```yaml
flutter:
  assets:
    - assets/logo.png
    - assets/login_hero.png
```

### Temporary Placeholder

If the final collage is not ready, use a clean Flutter-built placeholder panel with:

- Large repository shield icon/logo.
- Three mini information cards: "Teams", "Defense Schedule", "Repository".
- Small gold accent chips.

This lets the layout be implemented without blocking on image production.

## Login Card Specification

### Card

- Width: `360-400px`.
- Border radius: `12-16px`.
- Background: white.
- Shadow: soft, low opacity.
- Padding: `32px` desktop, `24px` mobile.
- Avoid nesting extra cards inside the login card.

### Form Fields

Use rounded filled inputs:

- Height: `48-52px`.
- Border radius: `10-12px`.
- Fill: `#FFFFFF` or `#F8FAFC`.
- Border: `#E5E7EB`.
- Focus border: `DefensysTokens.maroon`.
- Prefix icons:
  - Username: `Icons.badge_outlined` or `Icons.person_outline`.
  - Password: `Icons.lock_outline`.
- Password suffix icon must keep tooltip: "Show password" / "Hide password".

### Actions

Primary button:

- Text: `Log in`
- Height: `50-52px`.
- Background: `DefensysTokens.maroon`.
- Foreground: white.
- Radius: `10-12px`.
- Loading state: existing spinner.

Secondary actions:

- Remember me checkbox on the left.
- Forgot password link on the right.
- Keep remember-me helper text for web, but make it quieter below the row.

## Suggested Desktop Composition

Use a soft full-page layout instead of the current maroon wave.

```text
Scaffold
  background: #F8FAFC
  Stack
    subtle tinted background bands/shapes
    Center
      ConstrainedBox(maxWidth: 1120)
        Row
          Expanded(flex: 6)
            left story content
          SizedBox(width: 56)
          SizedBox(width: 380)
            login card
```

Responsive rules:

- `>= 1180px`: max content width around `1120-1200px`.
- `760px-1179px`: keep two columns but reduce gap and visual size.
- `< 760px`: use mobile layout.
- Minimum page height should avoid clipping on short laptop screens.

## Implementation Plan

1. Preserve all current login logic in [`login_screen.dart`](../frontend/lib/screens/login_screen.dart).
2. Replace `_buildWebLayout` presentation with a split layout.
3. Add helper widgets:
   - `_buildWebStoryPanel(...)`
   - `_buildLoginCard(...)`
   - `_brandLockup(...)`
   - `_loginHeroVisual(...)`
4. Reuse the existing `Form`, validators, `_login()`, `_buildSessionBanner()`, and `_sealLogo()` behavior.
5. Improve `_webInputDecoration()` so web inputs match the softer rounded style.
6. Keep `_buildMobileLayout()` behavior, but optionally align colors/radius with the new visual style.
7. Add `assets/login_hero.png` only when a final image is available.
8. Update widget tests only if visible text changes from `LOG IN` to `Log in`.
9. Run Dart formatting and targeted analyzer/tests.

## Test Checklist

Run from `frontend/`:

```powershell
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe format lib\screens\login_screen.dart
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib\screens\login_screen.dart
C:\src\flutter\bin\flutter.bat test test\widgets\login_screen_test.dart
```

Manual checks:

- Desktop web width `1440px`: split layout looks balanced.
- Laptop width `1024px`: no overlap, card remains readable.
- Tablet width around `760px`: layout still works or cleanly switches.
- Mobile width `390px`: mobile login still works and guest access remains visible.
- Text scaling: no clipped labels/buttons.
- Password visibility icon tooltip still works.
- Session-expired banner fits inside the card.
- Loading state disables repeated login submits.

## First Pass Recommendation

Start with a code-only layout refresh and a placeholder visual panel. That will immediately improve the login page while keeping the implementation low risk.

After the layout is stable, create `frontend/assets/login_hero.png` as a polished DefenSYS collage and add it to the left panel.

