# Cloro redesign — implementation plan

Status: **planned** (Nov 2026). Phase 10 of `IMPLEMENTATION_PLAN.md`.
Source: the product owner's change list of 13 Nov 2026. Each item below says what changes, where in the code, and how we know it's done.

## 0. Before we start (needs you)

| # | What | Why |
|---|---|---|
| 0.1 | **Commit and push `app/assets/logo.png`** (it is on your PC, not in the repository yet). Ideally 1024×1024 px, transparent background, the mark alone (no text). If you also have a version with the word "Cloro", add it as `app/assets/logo_wordmark.png`. | Icons, splash screen and in-app logo are generated from it. |
| 0.2 | Answer the **open decisions** in §12 (or accept the recommended defaults). | They change what gets built. |

## 1. Name: BookReel → Cloro

- App name on the phone: `android:label="Cloro"` (`app/android/app/src/main/AndroidManifest.xml`), `MaterialApp.title`.
- Every user-facing string: notifications (`lib/services/notifications.dart`), share text "Read it on Cloro" (`lib/features/share/share_sheet.dart`), profile share headline, onboarding, licences page, server-rendered share/invite pages (`server/src/…` HTML), Play listing copy in the docs.
- Code names (`BookReelApp`, package `book_reel`, repository name) stay for now: renaming them changes nothing users see and churns every file.
- **Done when:** no "BookReel" in any string a user can see (a test greps `lib/` string literals and the server's HTML templates).

## 2. Logo and app icon

- Add `flutter_launcher_icons` (dev dependency) → Android adaptive icon: the logo on a white background layer, with the safe-zone padding Android needs (the mark at ~66% of the canvas); monochrome layer for Android 13 themed icons.
- Add `flutter_native_splash` → launch screen: logo centred on white (light) / black (dark).
- In-app: logo + "Cloro" wordmark at the top of Today and on the onboarding welcome; small logo on share images and the session-end screen.
- **Done when:** the installed APK shows the Cloro icon and splash; screenshots of Today and onboarding show the logo.

## 3. Colour system: white and black, accent from the logo

What's wrong now: outside the reader the accent is a brownish amber (`#A4511A` / `#E9A85A` in `Kit.appLight` / `Kit.appDark`), and inside the reader every sheet, menu and toast is tinted with the scene's colour.

New rules (`lib/ui/kit.dart`, `lib/ui/theme.dart`):

| Token | Light | Dark |
|---|---|---|
| Background | `#FFFFFF` | `#000000` |
| Raised surface (cards, sheets, tab bar) | `#F5F5F5` | `#121212` |
| Hairlines | black 8% | white 12% |
| Text / secondary text | `#111111` / `#5C5C5C` | `#F2F2F2` / `#A3A3A3` |
| **Accent** | gradient `#FF3131 → #FF914D` (the logo) | same |

- The accent appears **only** on: the primary button, the selected tab icon, the streak flame, progress rings/bars, the "saved" state, and the logo. Everything else is black, white or grey.
- Text and icons **on** the gradient are near-black (`#111111`): 5.2:1 on `#FF3131` and 8.5:1 on `#FF914D` (WCAG AA). White would fail on the orange end (2.2:1). The gradient is never used as a text colour on white (`#FF3131` on white is only 3.7:1); for accent text on white (e.g. a link) use `#D91F1F`, a deeper red from the same family (5.0:1).
- **Reader chrome stops taking the scene's colour**: sheets, menus, toasts and the word sheet in the reader use the same neutral surfaces (black glass over dark scenes, white glass over light scenes). The scene is only the picture behind the text, plus the text colours calibrated for it (kept: they guarantee 7:1 contrast).
- Remove `ember` and the per-scene accent from chrome; keep per-scene *text* palettes.
- **Done when:** a test asserts no chrome colour outside {neutrals, the two accent stops}; screenshots of Today, Library, Settings, a reader sheet in light and dark.

## 4. Settings icon → gear

`Icons.tune_rounded` → `Icons.settings_rounded` in `today_screen.dart`, `profile_screen.dart` and the reader menu (`reader_screen.dart`). (Settings moves to the Profile tab header, as in Strava; see §8.)

## 5. Scenes: as many light as dark

Today: 7 of the 8 scenes are dusk/night (Forest at dusk, Café evening, Rain at night, Ocean after sunset, Night, Snow cabin, City at night); only Meadow is daytime.

Plan: **4 light + 4 dark** (Paper stays as a plain page that follows light/dark):

| Light (daytime) | Dark (evening/night) |
|---|---|
| **Meadow** — sunny meadow (as now) | **Night** — stars over mountains (as now) |
| **Forest morning** — sun through pines, birdsong (was Forest at dusk) | **Rain** — city lights through rain (as now) |
| **Beach** — bright surf, gulls, slow waves (was Ocean after sunset) | **City** — skyline at night (as now) |
| **Snow day** — white hills, soft snowfall (was Snow cabin) | **Café** — rainy evening, warm cup (as now) |

- Repaint the three converted scenes in `lib/ui/scenes.dart` (still base cached as one image + light sprite motion, so no speed cost), give each a light-ink palette in `lib/ui/vibes.dart` (dark text, pale scrim), recheck contrast in `test/ui/scene_palette_test.dart` (≥ 7:1 everywhere text can sit).
- Sounds stay (forest/birds, waves, snow wind all fit the daytime versions).
- The scene picker groups them under "Day" and "Night".
- **Done when:** 4 + 4 scenes, all pass the contrast test; picker shows two groups.

## 6. Reading tab: the reel, with nothing on screen

The reader becomes the **first tab** ("Reading") instead of a page opened over the app.

- The tab shows the book you're reading (the last one opened); with none, it shows the starter book or a "Pick a book" prompt that opens Library.
- **No close button**: you leave by switching tabs. Switching away keeps your place; coming back resumes at the same reel.
- **Distraction-free by default**: no top bar, no side rail, no progress text, no tab bar. Just the scene and the text.
  - **One tap** shows everything for 3 seconds (book/chapter, streak and goal, like/save/share/listen rail, the ⋯ menu, and the tab bar); a second tap or 3 s hides it again. Taps on words and highlights still work as now (the tap target is the empty space).
  - Swipe up/down still turns reels; swipe left saves, swipe right shares (below).
- **Better save/share swipes** (`lib/features/reader/cards/text_card.dart`):
  - the reel follows your finger 1:1 with a slight tilt (max ~6°) and a soft shadow;
  - the action reveals behind it: a bookmark (save) on one side and the share arrow on the other, growing and filling with the accent gradient as you near the threshold (~30% of the width);
  - a light haptic tick when you cross the threshold;
  - release past it: the reel flicks out and springs back with a small "Saved" / share sheet; release before it: it springs back (critically damped spring, ~250 ms, no bounce);
  - the old toast is replaced by the in-place confirmation.
- Opening a book from Library or Today switches to the Reading tab with that book.
- **Done when:** widget tests: tab shows the current book; no chrome after load; tap shows/hides chrome and the tab bar; switching tabs and back keeps the reel; swipe past/short of the threshold saves/springs back.

## 7. Open at the introduction, not the copyright page

Today the reader starts at the first spine item, which is often a cover, copyright, contents or dedication page.

- **EPUB** (`lib/core/parsing/epub_parser.dart`): use, in order, the nav document's `landmarks` (`epub:type="bodymatter"`), the OPF `<guide>` (`type="text"` / `start`), and the spine's `linear="no"` items; then a classifier that marks front matter by title (Cover, Title page, Copyright, Contents, Dedication, Epigraph, Also by, About the publisher…) and by content (©, "All rights reserved", ISBN, mostly links). **Introduction, Preface, Foreword and Prologue count as the start of the book.**
- **PDF** (`pdf_text_builder.dart`): skip leading pages that are mostly short lines, ©/ISBN or a table of contents; start at the first page with a chapter-style heading or a full paragraph.
- Store `startSid` on the book; a new book opens there. Front matter stays reachable from Contents (marked "Front matter").
- **Done when:** parser tests on EPUBs with each signal (landmarks, guide, linear=no, heuristics only) and a PDF fixture; the starter book opens on its first real chapter.

## 8. "How are you feeling?" picks the reading theme

- When a book is opened, a small sheet asks **"How are you feeling?"** with 6–8 one-tap moods; the book then opens in the matching scene. It preselects your last answer, and has *Skip* (keeps your current scene).
- Mood → scene (first match; light/dark follows the time of day or Settings):

| Mood | Scene |
|---|---|
| Calm | Meadow (day) / Night |
| Cozy | Café |
| Focused | Paper |
| Fresh / energised | Beach / Forest morning |
| Dreamy | Night |
| Low / reflective | Rain |
| Restless | Snow day / City |

- Paid plans: an extra option "Let the story decide" keeps AI-picked scenes.
- Settings → Reading: "Ask how I'm feeling when I open a book" (on by default).
- The mood is saved with each reading session (for the Today feed and Profile, e.g. "Read 12 min · 😌 calm").
- **Done when:** opening a book shows the sheet; each mood opens its scene; Skip keeps the scene; the setting turns it off.

## 9. Tabs and navigation

New dock, five tabs, **icons only** (no labels), larger icons (28 px, 56 px touch target), the active one in the accent gradient, an accessible name on each for screen readers:

1. **Reading** (main) — §6
2. **Library** — unchanged
3. **Notebook** — unchanged
4. **Today** — §10
5. **Profile** — §11 (settings gear in its header)

The Friends tab goes away: friends' activity moves into Today; your friends, invite code and league move into Profile. The dock is hidden in the Reading tab until you tap (§6).

## 10. Today tab: a Strava-style feed

A scrolling feed of reading activities, newest first:

- **Your goal** card at the top (today's ring, streak, "Continue reading" button).
- **Activity cards** for your sessions and your friends': avatar, name, time ago, book cover and title, the stats (minutes, cards, pages %, mood emoji), the quote they saved or shared (copyright limits apply), and **kudos** + **comments**.
- Milestones as cards: finished a book, 7/30/100-day streak, new personal best week.
- Pull to refresh; loads more as you scroll.
- Data: the existing activity/feed/kudos endpoints (`/v1/…friends feed`), extended with session stats, mood and comments (new `comments` table and endpoints on the server). Offline/no server: your own sessions only, from the local habit log.
- **Done when:** feed shows own + friends' sessions with kudos and comments; offline shows own sessions; server tests for comments.

## 11. Profile tab: Strava-style, redesigned header

**Header** (as you described):

```
[ photo ]  Name · she/her
           Short bio on one line
           📖 Reading: Pride and Prejudice
           Fantasy · History · Poetry          (up to 3)
           [Edit profile] [Share]                 ⚙
```

- Photo: a round avatar 88 px, cropped to fill (no letterboxing, centred on the face area from the crop the user picks in Edit profile, using an in-app crop step), with the accent ring when today's goal is done.
- Pronouns become a choice: **he/him, she/her, they/them**, or custom.
- Genres: pick **up to 3** (Edit profile enforces it; existing longer lists keep their first 3).

**Body**, like Strava's profile:

- **This week** — reading minutes per day (bar chart), total minutes, cards, books.
- **Streak** — current and best, freezes left, a calendar heatmap.
- **Stats** — this year / all time: minutes, cards, books finished, words read, average session.
- **Trophies** — milestones earned (streaks, books, personal bests).
- **Books** — currently reading (with progress rings) and finished.
- **Saved quotes** — the grid (as now).
- **Friends** — friends list, invite code, league (moved from the Friends tab; hidden when "Hide leaderboards" is on).
- **Done when:** widget tests for the header layout, pronoun choice, 3-genre limit, and each section with sample data.

## 12. Open decisions (recommended default in bold)

1. **Follower counts.** Strava shows followers/following; our design avoided public counts (DESIGN.md §8). → **Show a friends count; kudos counts visible only to the person who posted.**
2. **Mood question frequency.** → **Every time a book is opened, one tap, preselected, with Skip and a setting to turn it off.**
3. **Light vs dark scenes.** Convert three dark scenes to daytime (4 + 4, as above) or keep all 8 and paint 6 new light ones (7 + 7, much more art work). → **Convert (4 + 4)**; add more scenes later.
4. **Android package ID** (`app.bookreel.book_reel`): changing it later means a new Play listing. → **Change it now to `app.cloro.<something>`** (tell me your domain, e.g. `app.cloro.reader`), before the first Play upload.
5. **Chrome in the Reading tab.** → **Tap to show for 3 s** (alternatives: always-visible tiny icons; or swipe up from the bottom edge for the tab bar).

## 13. Order of work

| Step | Items | Size |
|---|---|---|
| 1 | Name (§1), gear icon (§4), colour system (§3) | M |
| 2 | Logo, icon, splash (§2) — needs 0.1 | S |
| 3 | Open at the introduction (§7) | M |
| 4 | Reading tab + distraction-free reel + tab dock (§6, §9) | L |
| 5 | Save/share swipe animation (§6) | M |
| 6 | Light/dark scenes (§5) and mood sheet (§8) | L |
| 7 | Profile redesign (§11) | L |
| 8 | Today feed + comments on the server (§10) | L |
| 9 | Docs, tests, CI, APK | S |

Steps 1–3 are independent and ship first; 4 and 5 go together; 6 needs 3's colour system; 7 and 8 replace the Friends tab, so they ship together with 4's new dock.
