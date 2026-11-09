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
| 0 | Foundations | Repo layout, Flutter scaffold, design tokens, lint, CI | — | ✅ Done |
| 1 | Reading engine | EPUB/PDF → chapters → blocks → sentences with stable IDs; rule segmenter; hard-word detector | 0 | ✅ Done |
| 2 | Reel reader MVP | Library, import, Reel mode + Page mode, themes, typography, TOC, TTS | 1 | ✅ Done |
| 3 | Reader tools | Highlights, notes, saved cards, word sheet + offline dictionary, word list, Notebook tab | 2 | ✅ Done |
| 4 | Habit engine | Dwell verification, daily/weekly goals, streaks & freezes, session complete, Today screen, reminders | 2 | ✅ Done |
| 5 | Sharing | Card & progress images, templates, share sheet, short-quote limit | 3, 4 | ✅ Done |
| 6 | AI segmentation backend | Claude pipeline (Haiku/Sonnet/Opus), validator/repairer, content-hash cache, quotas, Batch API; app client | 1 | ✅ Done (in-memory stores) |
| 7 | Accounts, sync & social | Firebase Auth, sync, friends, activity feed, kudos, leagues, clubs, challenges | 4, 6 | 🟡 Server logic done (verification, streaks, leagues); auth, persistence and social UI to do |
| 8 | Monetization & free-tier AI | Play Billing, entitlements, tier routing, regional pricing, on-device LLM | 6, 7 | 🟡 Tier routing & quotas done; billing and on-device model to do |
| 9 | Quality & launch | Gold-set evaluation, accessibility audit, performance, closed beta, Play listing | all | ⬜ Not started |

---

## Phase 0 — Foundations
- Flutter app (`app/`), Android only, package `app.bookreel`.
- `analysis_options.yaml` with `flutter_lints` + stricter rules.
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
- Library: import (file picker and "Open with"), grid with cover/progress, starter public-domain sample book bundled.
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
- Deep links (`bookreel.app/c/{id}`) arrive with the backend in Phase 7.

## Phase 6 — AI segmentation backend (`server/`)
- TypeScript + Fastify + Zod; `@anthropic-ai/sdk`.
- `POST /v1/segment`: validates the chapter payload, checks the content-hash cache, applies tier quota, calls the tier's model, validates and repairs, caches, returns cards.
- Model routing: Plus → `claude-haiku-5-5` (effort low), Pro → `claude-sonnet-5-5` (effort medium), Scholar → `claude-opus-5-5` (effort medium/high). Structured JSON output; server-side refusal fallback on Sonnet/Opus; Haiku refusal → retry on Sonnet → rules.
- Background chapters through the Message Batches API (50% cheaper): `POST /v1/segment/batch` + polling job.
- Validator/repairer shared logic: coverage, order, length bounds, sID checks, extras sanity.
- App client: `AiSegmentationClient` swaps AI cards in for upcoming chapters without moving the reading position; falls back to rule cards on any failure.

## Phase 7 — Accounts, sync & social
- **Done in this phase (server, in-memory):** reading-event verification, daily stats, streaks with freezes, weekly leagues (promotion and demotion), friends leaderboard, kudos.
- **To do:** Firebase Auth (Google sign-in) → ID token verification; Postgres via a repository layer (schema in DESIGN.md §7); Redis leaderboards; sync endpoints for highlights, saved cards and positions; Friends tab UI (feed, league, clubs, challenges); FCM digest notifications; App Links deep links; share preview web page.

## Phase 8 — Monetization & free-tier AI
- **Done:** tier → model routing, monthly AI-book quotas with regional limits (server).
- **To do:** Google Play Billing (`in_app_purchase`) + server verification + RTDN; paywall surfaces (Today/settings only, weekly cap); on-device open-weight LLM for the Free tier (`flutter_gemma` / MediaPipe) with a device capability check; rules-only fallback (already the default).

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
