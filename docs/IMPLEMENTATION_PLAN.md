# BookReel — Implementation Plan

| | |
|---|---|
| **Companion to** | [`DESIGN.md`](./DESIGN.md) · [`UX_DESIGN.md`](./UX_DESIGN.md) |
| **Status** | Living document; the status column is updated as work lands |
| **Date** | 2026-11-09 |

## Repository layout

```
book_reel/
├── app/        Flutter Android app (offline-first; works without the backend)
├── server/     TypeScript backend: AI segmentation, activity verification, streaks, leagues
├── docs/       Design, UX and this plan
└── .github/    CI (analyze + test for app and server)
```

Guiding rule: **every phase ends with something usable, plus tests.** The app is built offline-first. Phases 0–5 make a complete single-player reading app with no server. The backend then adds AI segmentation, social features and billing on top, without changing how the app reads books.

---

## Phase overview

| # | Phase | Outcome | Depends on | Status |
|---|---|---|---|---|
| 0 | Foundations | Repo layout, Flutter scaffold, design tokens, lint, CI | — | ✅ Done (CI green: analyze, tests, APK build) |
| 1 | Reading engine | EPUB/PDF → chapters → blocks → sentences with stable IDs; rule segmenter; hard-word detector | 0 | ✅ Done |
| 2 | Reel reader MVP | Library, import, Reel mode + Page mode, themes, typography, TOC, TTS | 1 | ✅ Done, except "Open with" from other apps |
| 3 | Reader tools | Highlights, notes, saved cards, word sheet + offline dictionary, word list, Notebook tab | 2 | ✅ Done |
| 4 | Habit engine | Dwell verification, daily/weekly goals, streaks & freezes, session complete, Today screen, reminders | 2 | ✅ Done |
| 5 | Sharing | Card & progress images, templates, share sheet, short-quote limit | 3, 4 | ✅ Done; share links added in Phase 7 |
| 6 | AI segmentation backend | Claude pipeline (Haiku/Sonnet/Opus), validator/repairer, content-hash cache, quotas, Batch API; app client | 1 | ✅ Done, persisted in Postgres; tested against a mocked Claude client, no live API call yet |
| 7 | Accounts, sync & social | Firebase Auth, sync, friends, activity feed, kudos, leagues, clubs, challenges | 4, 6 | 🟡 Mostly done: Postgres persistence, server-verified activity, leagues, invite-code friends, feed and kudos, notebook/position sync, share links with web previews, Friends tab. To do: Google sign-in in the app (needs a Firebase project), push notifications (FCM), App Links handling in the app, clubs and challenges |
| 7b | Social-reel UI | Snack cards, post layout, gestures, calm animated scenes | 6, 7 | ✅ Done (the AI music it also added was replaced by scene sounds in 7e) |
| 7c | Full AI direction | Two-pass AI (structure on the tier model, per-card art direction on Haiku), full-screen lyric typography, 8 scenes with AI Auto scene, v2 pricing | 7b | ✅ Done (verified against mocked Claude; live-API pilot still to do) |
| 7d | Calm reels | Scene-matched text palettes with measured contrast, spotlight reels (one text size per reel), text kept in the middle of the screen with long text continued on the next reel, fonts chosen per book (AI on paid tiers, rules on device) | 7c | ✅ Done (feed is built on the UI thread: fine for novels, move to an isolate if very long books open slowly) |
| 7e | Scene sounds | AI music removed (no licensing needed); each scene plays its own ambient sound from bundled public-domain/CC recordings, for every tier, mutable in one tap | 7d | ✅ Done |
| 7f | Immersive UI, profile, highlights | App-drawn sheets/dialogs/toasts/controls over the scene, compact settings, tappable streak and goal, reels share arrow, smoother scenes; Instagram-style profile; highlights with drag handles | 7e | ✅ Done |
| 7g | Natural voice | Read-aloud with a neural voice (Kokoro via `POST /v1/tts`, cached on server and phone, next reel prefetched), phone voice fallback with the best installed voice | 7f | ✅ Done in code; needs `TTS_API_KEY` on the server |
| 7h | Light & dark app, scenes in the reader | Screens outside the reader use a plain light or dark theme (Settings → Appearance: system default, light, dark); scenes appear only while reading (and on its session-end screen); onboarding previews the scene in a window | 7g | ✅ Done |
| 8 | Monetization & free-tier AI | Play Billing, entitlements, tier routing, regional pricing, on-device LLM | 6, 7 | 🟡 Done in code: Play subscriptions with server verification and real-time notifications, enforced plans, tier routing, regional quotas, and the Free plan's on-device model (LiteRT-LM). To go live: Play Console products + service account (checklist below). Paywall surfaces to do |
| 10 | Cloro redesign | New name and logo, white/black colour system with the logo gradient as accent, 4 light + 4 dark scenes, Reading tab with a distraction-free reel, open at the introduction, mood picks the scene, Strava-style Today feed and Profile — see `docs/CLORO_PLAN.md` | 8 | ⬜ Planned |
| 9 | Quality & launch | Gold-set evaluation, accessibility audit, performance, closed beta, Play listing | all | ⬜ Not started |

### Verification so far
- App (Nov 2026): `flutter analyze` clean; 136 tests. Server: 58 tests. Earlier: app 50 tests (parsers, segmenter, lexicon, habit engine, feed, data layer, AI client contract, two-device sync against a fake server, reader and Friends widget tests).
- Server: `tsc` clean; 35 tests against real Postgres SQL via embedded PGlite (segmenter, validator, prompt, Claude client against a mocked SDK, service incl. quota/refusal/batch, activity/streaks/leagues/friends, sync, share pages, Firebase token verification, HTTP API, data surviving a restart).
- Android: CI builds a debug APK (first green run: CI #2). `flutter_local_notifications` is pinned to 22.x because 23.0 needs compileSdk 37, which Flutter 3.47's Android Gradle plugin (9.1) doesn't support yet.
- **Not yet verified:** the app on real devices (behaviour and performance), and a live Claude call with a real API key.

### Deviations from DESIGN.md
- App-side local storage uses an atomic JSON-file store behind a small interface (`app/lib/data/json_store.dart`) instead of Drift. It is enough for single-device data; switch to Drift/SQLite when sync lands.
- Material You dynamic colour was dropped: `dynamic_color` 2.1 targets the new standalone `material_ui` package and is type-incompatible with Flutter 3.47's built-in Material. The app uses a fixed ember seed scheme.


---

## Phase 0 — Foundations
- Flutter app (`app/`), Android only, package `app.bookreel`.
- `analysis_options.yaml` with `flutter_lints`.
- Design system: `ThemeData` (Material 3) + `ReadingTheme` `ThemeExtension` (Paper, White, Sepia, Dark, Black), bundled reading fonts (Literata, Atkinson Hyperlegible).
- State: Riverpod. Navigation: go_router with a 4-tab `StatefulShellRoute` (Today, Library, Notebook, Friends) + full-screen reader route.
- CI: GitHub Actions runs `flutter analyze`, `flutter test`, and the server's `npm test`.

**Exit criteria:** app launches to the Today tab; CI is green.

## Phase 1 — Reading engine (pure Dart, fully unit-tested)
| Component | Notes |
|---|---|
| Content model | `Book → Chapter → Block → Sentence`; sentence ID `c{ch}.b{blk}.s{n}` is the single position model |
| Sentence splitter | Rule-based; handles abbreviations, initials, decimals, ellipses, quotes and brackets |
| EPUB parser | `archive` (unzip) + `xml` (OPF/NCX/nav) + `html` (XHTML → blocks: heading, paragraph, quote, list, dialogue); spine order; TOC titles |
| PDF extractor | `pdfrx` (PDFium) text per page → header/footer removal, de-hyphenation, paragraph rebuild, heading heuristics; scanned-PDF detection |
| Rule segmenter | Boundary scoring (paragraph, heading, discourse markers, back-references, dialogue/list protection) + dynamic programming inside the length band (Bite/Standard/Deep) |
| Hard-word detector | Bundled Zipf frequency list (from `wordfreq`) + user level thresholds; skips proper nouns |
| Content hash | SHA-256 of file bytes (cache key for segment maps) |

**Exit criteria:** a 300-page EPUB is parsed and segmented on device in < 3 s; no card breaks a sentence; ≥ 95% of cards fall inside the length band.

## Phase 2 — Reel reader MVP
- Library: import via the file picker ("Open with" from other apps is still to do), grid with cover/progress, a bundled public-domain starter book.
- Reader: vertical pager, card types (text, chapter, recap, recall, reflect, milestone), segmented goal bar, fading chrome, bottom action row, long cards scroll inside the card, position anchored to sentence IDs.
- Page mode toggle (continuous chapter text) at the same position.
- Settings: theme, font, size, line height, letter spacing, card length, key-point style, hard-word underline, TTS.
- TTS read-along (`flutter_tts`).

**Exit criteria:** import → first card in < 10 s; 60 fps swipe on a mid-range device; position survives restarts and card-length changes.

## Phase 3 — Reader tools
- Highlights (double-tap sentence, 4 tints, notes), saved cards (with text snapshot), collections.
- Word sheet: dictionary meaning (bundled WordNet subset), pronunciation via TTS, AI meaning-in-context when available, add to word list.
- Notebook tab: Saved, Highlights, Words, Reflections. Markdown export via share.

## Phase 4 — Habit engine
- Dwell-time verification (`dwell ≥ 0.35 × words / wpm`), learned WPM.
- Daily goal (cards or minutes) and weekly-goal mode; streak with freezes (per tier) and 48 h repair; time-zone-safe local dates.
- Segmented goal bar, Session Complete screen (peak-end), milestone celebrations with reduced-motion support.
- Today screen: goal ring, streak, continue-reading card.
- Daily reminder notification using the user's habit anchor; quiet hours.

## Phase 5 — Sharing
- Off-screen rendering of 9:16 / 4:5 / 1:1 images; templates (Quote, Minimal, Dark, Gradient, Paper).
- Share sheet with live preview; `share_plus`; copy text.
- 75-word limit for copyrighted books (public-domain books unlimited).
- Progress cards (streak, book finished, weekly recap).
- Share links with web previews (`/c/{id}`) are served by the backend (Phase 7); opening them directly in the app (App Links) is still to do.

## Phase 6 — AI segmentation backend (`server/`)
- TypeScript + Fastify + Zod; `@anthropic-ai/sdk`.
- `POST /v1/segment`: validates the chapter payload, checks the content-hash cache, applies tier quota, calls the tier's model, validates and repairs, caches, returns cards.
- Model routing: Lite → `claude-haiku-5-5` (effort low), Plus → `claude-sonnet-5-5` (effort medium), Pro → `claude-opus-5-5` (effort medium/high), Scholar → `claude-fable-5-2` (effort medium). Structured JSON output; server-side refusal fallback on Sonnet/Opus/Fable; Haiku refusal → retry on Sonnet → rules.
- Background chapters through the Message Batches API (50% cheaper): `POST /v1/segment/batch` + polling job.
- Validator/repairer shared logic: coverage, order, length bounds, sID checks, extras sanity.
- App client: `AiSegmentationClient` swaps AI cards in for upcoming chapters without moving the reading position; falls back to rule cards on any failure.

## Phase 7 — Accounts, sync & social
**Done**
- Server storage on Postgres (`server/src/db`): node-postgres when `DATABASE_URL` is set, otherwise embedded PGlite on disk (`./data/pglite`). Append-only migrations. All stores and services persist.
- Identity: anonymous device accounts (`x-device-id`) work today. Firebase ID tokens are verified when `FIREBASE_PROJECT_ID` is set; the first sign-in on a device links to that device's existing account, so no progress is lost.
- Reading events are queued on the phone (works offline) and uploaded in batches; the server re-verifies dwell time before anything counts toward streaks or leagues.
- Weekly leagues (24 per group, ranked by goal days then minutes, top 5 up / bottom 5 down), invite-code friendships (mutual), friends board, activity feed with kudos only.
- Sync of highlights, saved cards, words, reflections, likes and reading positions across devices of the same account (last write wins per item, deletions propagate).
- Share links (`/c/:id`) with server-rendered preview pages and the 75-word limit enforced again on the server; invite page (`/i/:code`); `/.well-known/assetlinks.json` for App Links.
- Friends tab: invite code + share, league table, friends board, feed with kudos, add friend by code, offline fallback.

**To do (needs your accounts or a product decision)**
- Google sign-in in the app: create a Firebase project, add the Android app (SHA-1/SHA-256 of the signing key), then add `firebase_auth` + `google_sign_in` and send the ID token as `Authorization: Bearer`. The server side is ready.
- Push notifications for kudos/friend activity (FCM, same Firebase project). Today the daily reminder is local only.
- App Links in the app (open `/c/…` and `/i/…` links directly in BookReel) once the domain is live: set `ANDROID_CERT_SHA256` on the server and add an intent filter.
- Clubs and challenges (DESIGN.md §2.9).
- Production hosting: Cloud Run + Cloud SQL (Postgres). Redis is not needed at current scale; league tables are computed from Postgres.

## Phase 8 — Monetization & free-tier AI
- **Done:** tier → model routing, monthly AI-book quotas with regional limits (server).
- **Done (code):** Google Play Billing. The app (`app/lib/services/billing.dart`) sells `bookreel_lite`, `bookreel_plus`, `bookreel_pro` and `bookreel_scholar` subscriptions with `monthly` and `yearly` base plans at Play's local prices, shows free trials, switches plans with proration and restores purchases. Every purchase is verified by the server (`server/src/billing/play.ts`: Play Developer API `purchases.subscriptionsv2` with a service account) before the plan changes and is acknowledged only after that. Real-time developer notifications (`POST /v1/billing/rtdn`) keep renewals, cancellations, holds and upgrades in step. With `BILLING_ENFORCED=1` the server serves the verified plan to every AI endpoint instead of the plan the app claims.
- **Done (code):** on-device AI for the Free plan. A small open-weight model, downloaded once from Settings → On-device AI, runs on the phone through Google's LiteRT-LM (`flutter_edge_ai` 2.6.0 + `flutter_edge_ai_litertlm` 1.20.0, pinned). Choices: **Qwen3 0.6B** (345 MB, the default) and **Gemma 4 E2B** (2.0 GB, phones with 8 GB of memory); both Apache 2.0, ungated, pinned by commit and SHA-256 in the engine's catalog. A device check (Android 11+, 64-bit ARM, memory, free space) runs first; the model loads on first use and is released after 2 idle minutes. It writes a recap and a quick check at the end of every block of cards (10, or 15 for Snack), a recap at each chapter's end, the next chapter's teaser, and word meanings in context (asked when a word is tapped, ahead of background work). It never cuts cards or changes text: rule cards stay, and every reply passes checks (format, length, a quick-check answer grounded in the book's key sentence) or is dropped. Code: `lib/services/on_device_ai.dart` (seam, download, queue), `lib/data/local_ai.dart` (prompts, checks, plan, storage), `lib/services/litert_runtime.dart` (the engine; only `main.dart` imports it).
- **To do:** paywall surfaces beyond the plan sheet (Today/settings only, weekly cap); measure on-device speed and recap quality on low and mid-range phones (Phase 9).

## Launch checklist (needs your accounts)
These steps need your own accounts, keys or decisions, so they can't be done in code. In order:

1. **Server hosting.** Create a Google Cloud project. Deploy `server/` to Cloud Run with a Cloud SQL (Postgres) database: set `DATABASE_URL`, `PUBLIC_BASE_URL` (your domain) and the keys below as **secrets** (Secret Manager), never in code.
2. **AI keys.** An Anthropic API key (`ANTHROPIC_API_KEY`, with standard 30-day retention so Scholar's Fable model works) and a speech key (`TTS_API_KEY`; default provider DeepInfra running Kokoro-82M, about $1 per million characters; any OpenAI-compatible speech API works via `TTS_BASE_URL`/`TTS_MODEL`). Run a small pilot and compare real `ai_usage` costs with DESIGN.md §5.
3. **Release signing.** Create an upload key and Play App Signing; replace the debug signing in `app/android/app/build.gradle.kts`, choose the final application ID (`PLAY_PACKAGE_NAME`).
4. **Play Console** ($25 one-time developer account). Create the app, the store listing, the content rating and the Data safety form, plus a privacy policy page (DPDP/GDPR).
5. **Subscriptions.** In Play Console create the four products (`bookreel_lite`, `bookreel_plus`, `bookreel_pro`, `bookreel_scholar`), each with `monthly` and `yearly` base plans and regional prices (DESIGN.md §6.1), plus a 7-day free-trial offer.
6. **Billing verification.** Create a Google Cloud service account, grant it access in Play Console (Users and permissions → financial data and order management), save its JSON key as `PLAY_SERVICE_ACCOUNT_JSON`. Create a Pub/Sub topic for real-time developer notifications with a push subscription to `https://<server>/v1/billing/rtdn?secret=<PLAY_RTDN_SECRET>`, and set `BILLING_ENFORCED=1` once purchases verify end to end.
7. **Google sign-in and push.** Create a Firebase project (adds the app's SHA-1/SHA-256), set `FIREBASE_PROJECT_ID`, then add `firebase_auth`/`google_sign_in` and FCM to the app (Phase 7 to-do).
8. **App Links.** Point your domain at the server, set `ANDROID_CERT_SHA256` and add the intent filter (Phase 7 to-do).
9. **Closed testing.** Upload a release build to an internal/closed test track, add licence testers (test purchases cost nothing), test buying, switching, cancelling and restoring plans, then run the Phase 9 checks (accessibility, low-end phones) before production.

## Phase 9 — Quality & launch
- Segmentation gold set (40 books, human boundaries) + evaluation script; gate prompt/model changes on it.
- Accessibility audit (TalkBack, 200% text, contrast), golden tests for card types × themes × text scales.
- Performance profiling on low-end devices; APK size budget.
- Comprehension study (Reel vs Page mode), diary study, closed beta, Play Store listing, privacy policy (DPDP/GDPR).

---

## How to run

```bash
# App
cd app && flutter pub get && flutter test && flutter run

# Server
cd server && npm install && npm test && ANTHROPIC_API_KEY=... npm run dev
```

Point the app at the server with `--dart-define=BOOKREEL_API=http://10.0.2.2:8787`. Without this flag the app uses on-device rule segmentation only (the Free tier experience).
