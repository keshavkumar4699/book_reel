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
- **Android package ID: `app.sweatik2.cloro`** (`applicationId` and `namespace` in `app/android/app/build.gradle.kts`, the Kotlin package of `MainActivity`). Phones with the old build installed get Cloro as a separate app; uninstall the old one.
- Code names (`BookReelApp`, Dart package `book_reel`, repository name) stay for now: renaming them changes nothing users see and churns every file.
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

## 6. Reading tab: the reel screen, overhauled

The reader becomes the **first tab** ("Reading") instead of a page opened over the app.

- The tab shows the book you're reading (the last one opened); with none, the starter book or a "Pick a book" prompt that opens Library.
- **No close button**: you leave by switching tabs. Switching away keeps your place; coming back resumes at the same reel. Opening a book from Library or Today switches to this tab.

**Controls and focus mode**

- A book opens in **focus mode**: just the scene and the text. No top bar, no side rail, no tab bar.
- **Tap empty space** (not a word): all controls appear, including the tab bar, and **stay** until you tap the **focus button (eye icon)**, which hides them again.

**Gestures**

| Gesture | On a word | On empty space |
|---|---|---|
| Tap | The word's meaning (word sheet: in this sentence, dictionary, add to word list) | Show all controls |
| Long press | **Highlighter** starts on that word: drag the handles to extend it (as now, word by word) | **Options sheet** (below) |
| Swipe up / down | Next / previous reel | same |
| Swipe left / right | Save / share (with the new animation) | same |

- **Highlighter colour matches the scene**: on dark scenes a light tint of the scene's own colour with dark text on it; on light scenes a deep tint with light text on it, so highlighted words always stay clearly readable (≥ 4.5:1, measured in a test for every scene). The 4 colour choices become 4 tints of the same family.

**Options sheet** (long press on empty space, or the ⋯ button): theme (scene picker, Day / Night), scene sound on/off, contents, page mode, daily goal, gestures (the guide), settings, "This cut feels wrong".

**Right-hand buttons**, top to bottom: **like, save, note, share, listen, streak count, goal count, options (⋯)**.

- **Note** opens an empty box for your own thoughts on this reel (saved to the Notebook with the reel's text as context). It no longer manages highlights; highlights are edited by long-pressing them.
- Streak and goal open their sheets (as now).

**Progress line**: the chapter progress at the top becomes one thin continuous line that fills smoothly as you read (instead of one dash per card), in the accent gradient on a faint track.

**Save / share swipes** (`lib/features/reader/cards/text_card.dart`):

- the reel follows your finger 1:1 with a slight tilt (max ~6°) and a soft shadow;
- a bookmark (save) and the share arrow reveal behind it, growing and filling with the accent gradient as you near the threshold (~30% of the width);
- a light haptic tick at the threshold;
- past it: the reel flicks out and springs back with an in-place "Saved" (or the share sheet); short of it: it springs back (critically damped, ~250 ms, no bounce).

**Done when:** widget tests: the tab shows the current book; focus mode on open; tap on empty space shows controls and they stay until the eye is tapped; tap on a word opens the word sheet; long press on a word starts a highlight, on empty space opens the options sheet; button order; the note box saves a thought; the progress line fills; swipe past/short of the threshold saves/springs back.

## 7. Open at the introduction, not the copyright page

Today the reader starts at the first spine item, which is often a cover, copyright, contents or dedication page.

- **EPUB** (`lib/core/parsing/epub_parser.dart`): use, in order, the nav document's `landmarks` (`epub:type="bodymatter"`), the OPF `<guide>` (`type="text"` / `start`), and the spine's `linear="no"` items; then a classifier that marks front matter by title (Cover, Title page, Copyright, Contents, Dedication, Epigraph, Also by, About the publisher…) and by content (©, "All rights reserved", ISBN, mostly links). **Introduction, Preface, Foreword and Prologue count as the start of the book.**
- **PDF** (`pdf_text_builder.dart`): skip leading pages that are mostly short lines, ©/ISBN or a table of contents; start at the first page with a chapter-style heading or a full paragraph.
- Store `startSid` on the book; a new book opens there. Front matter stays reachable from Contents (marked "Front matter").
- **Done when:** parser tests on EPUBs with each signal (landmarks, guide, linear=no, heuristics only) and a PDF fixture; the starter book opens on its first real chapter.

## 8. Mood: learn when you read how, then pick the scene for you

**Learning phase.** For the first two weeks (or until about 15 answers), when you open a book a small sheet asks **"How are you feeling?"** — at most once every 3 hours, so it isn't asked on every open. Moods: calm, cozy, focused, energised, dreamy, reflective, restless. Each answer is stored with when it was given (hour, weekday) and how the session went (minutes read, cards).

**Then the AI picks.** Once there's enough data, the app **predicts the mood that suits you right now** and opens the book in that mood's scene, with a small chip at the top, e.g. "😌 Calm · change", to correct it (a correction is also learnt from). Asking stops, except a check-in about once a week.

**The model: Google's Gemma.**

- On the phone when Gemma is downloaded: the on-device AI (§ Phase 8) gains **Gemma 4 E2B** as the model for this (already offered; 2 GB, phones with 8 GB of memory).
- Otherwise on the server: `POST /v1/mood/suggest` calls a hosted **Gemma** model (Gemma 3 4B/12B instruct) through the same OpenAI-compatible provider as the voice (DeepInfra; `MOOD_MODEL`, `MOOD_BASE_URL`, key in the secret store). Only the mood log is sent (time, weekday, mood, minutes): no book text.
- The prompt gives Gemma the log summarised as counts by time of day and weekday, plus recent sessions, and asks for one mood and a one-line reason; the reply must be one of the 7 moods or it's ignored.
- Offline / no model: the most frequent mood for that time slot (morning, afternoon, evening, night) and weekday type.
- Settings → Reading: "Pick my scene from my mood" (on), "Ask how I'm feeling" (only while learning / weekly / never).

**Mood → scene** (light or dark from the time of day and Appearance):

| Mood | Scene |
|---|---|
| Calm | Meadow (day) / Night |
| Cozy | Café |
| Focused | Paper |
| Energised | Beach / Forest morning |
| Dreamy | Night |
| Reflective | Rain |
| Restless | Snow day / City |

Paid plans keep "Let the story decide" (AI-picked scenes per chapter) as an option.

**Done when:** tests for the ask-rate limit, the learning → predicting switch, the fallback predictor, server `/v1/mood/suggest` with a fake Gemma (valid/invalid replies), and the chip's correction being stored.

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
[ photo ]  Name · she/her            128 followers · 96 following
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

## 12. Decisions (13 Nov 2026)

1. **Followers and following: public counts**, Strava-style one-way follows (§11). DESIGN.md §8's "no public counts" guardrail is retired for these two numbers; kudos counts stay visible only to the author.
2. **Mood:** asked at intervals while learning, then **Gemma** predicts it (§8).
3. **Scenes:** convert 3 night scenes to daytime (4 + 4, §5).
4. **Android package ID: `app.sweatik2.cloro`** (§1).
5. **Controls:** tap on empty space shows them; they stay until the **focus (eye)** button hides them (§6).

## 13. Order of work

| Step | Items | Size |
|---|---|---|
| 1 | Name and package ID (§1), gear icon (§4), colour system (§3) | M |
| 2 | Logo, icon, splash (§2) — needs 0.1 | S |
| 3 | Open at the introduction (§7) | M |
| 4 | Reading tab + reel overhaul (focus mode, gestures, buttons, note box, progress line) + tab dock (§6, §9) | L |
| 5 | Save/share swipe animation (§6) | M |
| 6 | Light/dark scenes (§5), mood learning + Gemma suggestion (§8) | L |
| 7 | Profile redesign + followers/following (§11) | L |
| 8 | Today feed + comments on the server (§10) | L |
| 9 | Docs, tests, CI, APK | S |

Steps 1–3 are independent and ship first; 4 and 5 go together; 6 needs 3's colour system; 7 and 8 replace the Friends tab, so they ship together with 4's new dock.
