# BookReel

Read books as a feed of short "reel" cards: real pages from your EPUBs and PDFs, cut by AI at the right places, with streaks, goals, highlights, word meanings and one-tap sharing.

| Document | What it covers |
|---|---|
| [`docs/DESIGN.md`](docs/DESIGN.md) | Product & technical design, AI pipeline, cost model, pricing |
| [`docs/UX_DESIGN.md`](docs/UX_DESIGN.md) | UX/UI guidelines grounded in behavioural research |
| [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) | Phases, status, and what's left |

## Repository layout

```
app/      Flutter Android app (offline-first; works fully without the server)
server/   TypeScript backend: Claude segmentation, reading verification, streaks, leagues
docs/     Design documents
```

## App

Requires Flutter 3.47+ and the Android SDK.

```bash
cd app
flutter pub get
flutter test
flutter run
```

Without a server the app runs in **Free** mode: cards are cut on the device by the rule segmenter. To use AI cards, start the server and point the app at it (the Android emulator reaches the host at `10.0.2.2`):

```bash
flutter run --dart-define=BOOKREEL_API=http://10.0.2.2:8787
```

Then pick Plus, Pro or Scholar under **Settings → AI plan**. Billing is not live yet, so the plan setting only switches which Claude model the server uses.

With a server configured the app also syncs your notebook and reading position, uploads reading activity, and turns on the Friends tab (league, friends board, feed with kudos, invite codes) and share links.

What's in the app: library and EPUB/PDF import, a starter public-domain book, the reel reader (chapter, text, recap, recall, reflect and milestone cards), page mode, themes and typography, read-aloud, highlights and notes, saved cards, an offline dictionary with hard-word underlines, a word list with spaced review, a notebook with Markdown export, daily or weekly goals with streak freezes, a session-complete screen, gentle daily reminders, share images (quotes and progress), onboarding, settings and a progress profile.

## Server

Requires Node 22+.

```bash
cd server
npm install
npm test
ANTHROPIC_API_KEY=... npm run dev     # http://localhost:8787
```

| Endpoint | Purpose |
|---|---|
| `POST /v1/segment`, `GET /v1/segment/jobs/:id` | AI cards for 1–3 chapters (background chapters use the Batch API) |
| `GET /v1/me`, `PUT /v1/me/profile`, `GET /v1/me/streak`, `GET /v1/me/ai-usage` | Account, invite code, streak, AI quota |
| `POST /v1/activity/batch`, `POST /v1/activity/book-finished` | Reading events, re-verified server-side |
| `GET /v1/leagues/current`, `GET /v1/leaderboards/friends` | Weekly league and friends board |
| `POST /v1/social/follow-code`, `DELETE /v1/social/follow/:userId`, `GET /v1/feed`, `POST /v1/activities/:id/kudos` | Friends, feed and kudos |
| `GET /v1/sync?since=`, `PUT /v1/sync` | Notebook and reading-position sync |
| `POST /v1/share`, `GET /c/:id`, `GET /i/:code`, `GET /.well-known/assetlinks.json` | Share links, preview pages, invites, App Links |

Configuration (all optional locally):

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | `postgres://…` for Postgres; otherwise an embedded PGlite database in `./data/pglite` |
| `ANTHROPIC_API_KEY` | Claude credentials (needed only for AI cards) |
| `FIREBASE_PROJECT_ID` | Enables Google sign-in (Firebase ID tokens); without it, accounts are per device |
| `PUBLIC_BASE_URL` | Base URL for share and invite links |
| `ANDROID_CERT_SHA256` | Signing-certificate fingerprints for Android App Links |
| `MUSIC_CATALOG` | Soundtrack catalog JSON (default `./music/catalog.json`; see `music/catalog.example.json`) |

### AI soundtrack (paid tiers)

During segmentation Claude also tags each card with a **mood** (calm, reflective, hopeful, joyful, playful, romantic, mysterious, tense, sad, epic) and an **energy** (1–5). The app picks a matching track from the server's catalog, changes music only when a new mood holds for two cards (or a chapter starts) and at most every 30 seconds, crossfades, lowers the volume during read-aloud, and shows each track's credit when it starts.

**Licensing:** the catalog ships empty. Only add tracks you have the rights to stream inside the app. NoCopyrightSounds (NCS) music is free for online videos and streams, but use in an app or a paid feature needs a license from NCS. Every catalog entry must include a license note and the attribution text; entries without them are rejected.

Models by tier: Plus → `claude-haiku-5-5`, Pro → `claude-sonnet-5-5`, Scholar → `claude-opus-5-5` (`server/src/config.ts`).

## Licenses of bundled data

Fonts: Literata and Atkinson Hyperlegible (SIL OFL). Dictionary: WordNet 3.0 (WordNet License). Word frequencies: wordfreq (CC BY-SA 4.0). Starter book: *Alice's Adventures in Wonderland* (public domain). See `app/assets/lexicon/README.md`.
