# Cloro

_Formerly BookReel. Android package `app.sweatik2.cloro`._

Read books as a feed of short "reel" cards: real pages from your EPUBs and PDFs, cut by AI at the right places, on calm moving scenes, with streaks, goals, highlights, word meanings, one-tap sharing, and a Strava-style feed of your reading and the readers you follow.

| Document | What it covers |
|---|---|
| [`docs/DESIGN.md`](docs/DESIGN.md) | Product & technical design, AI pipeline, cost model, pricing |
| [`docs/UX_DESIGN.md`](docs/UX_DESIGN.md) | UX/UI guidelines grounded in behavioural research (Revisions 1–12) |
| [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) | Phases, status, and the launch checklist |
| [`docs/CLORO_PLAN.md`](docs/CLORO_PLAN.md) | The Cloro redesign (steps 1–9, all done) |
| [`docs/PRODUCTION_PLAN.md`](docs/PRODUCTION_PLAN.md) | What's left for a production launch, in order |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | Deploying the server (Cloud Run), release signing, error reporting and alerts |

## The app at a glance

Five tabs, icons only: **Reading · Library · Notebook · Today · Profile**.

- **Reading.** The reels of the book you're reading, and the app opens here.
  - A book opens at its introduction, not the copyright page.
  - It opens in **focus mode**: just the picture and the text. Tap empty space to show the controls; they hide on their own 4 seconds after your last touch (or tap empty space again). With TalkBack on they stay until you hide them.
  - Tap a word for its meaning. Long-press a word to highlight it, or long-press empty space for options.
  - Swipe left to save, right to share.
  - The right rail: like, save, note, share, listen, streak, goal, options.
- **Your pictures.** Each book opens on a random picture from `app/assets/images/backgrounds/` (never the one shown last). The row at the top of the reader (with the controls) switches it on the go, as does options → Background. The app measures each picture and shades it just enough for the text to stay readable, with light or dark text, whichever suits it. Until you add pictures, it uses its 8 painted scenes (4 by day, 4 by night).
- **Your music.** Each book starts a random track from `app/assets/sounds/music/` and plays on through them; previous, pause and next sit at the top with the controls. Until you add music, it plays calm sound loops (rain, café, surf, birdsong…).
- **Today.** Your goal ring, streak and the book to continue. Below them, the **Activity** feed: your reading sessions and milestones and those of readers you follow, with kudos and comments. Offline it shows your own sessions.
- **Profile.**
  - Photo (with a crop step), name · pronouns, public **followers · following**, bio, what you're reading and up to 3 genres.
  - This week, streak, stats, trophies, books and saved quotes.
  - Find people by @username.
- **Look.** Black, white and greys everywhere except the reader's picture. The logo red appears only on the logo, the streak flame, the liked heart and badges. Flat lists, with lines only between groups.

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

Then pick Lite, Plus, Pro or Scholar under **Settings → Plan**. Until the Play subscriptions exist (`docs/IMPLEMENTATION_PLAN.md`, "Launch checklist"), the plan setting only switches which Claude model the server uses; once they do, the same sheet sells them through Google Play. Start the server with `TTS_API_KEY` set to hear the natural read-aloud voice.

### Try it on a phone

Every CI run builds release APKs (artifact **bookreel-release-apk** on the run's page under *Actions → CI*). Install `app-arm64-v8a-release.apk` on most phones, or `app-armeabi-v7a-release.apk` on older ones. They are signed with the debug key for now. Judge smoothness on these: debug builds (`flutter run` without `--release`) run several times slower. They run without a server unless you set the repository variable `BOOKREEL_API` (GitHub → Settings → Secrets and variables → Actions → Variables) to your deployed server's `https://` address; the next CI run builds it in. To build one yourself:

```bash
flutter build apk --release --split-per-abi
```

With a server configured the app also:
- syncs your notebook and reading position;
- uploads reading activity and sessions;
- turns on following, the Today feed (kudos and comments), the League page (league, board, invite codes) and share links.

How a reel looks (details and sources in `docs/UX_DESIGN.md`, Revision 4):

- **Colours come from the picture.** Each picture is measured for its own text colours and shade (above); each of the 8 painted scenes has a palette of its own. Text keeps at least 7:1 contrast where it sits; `test/ui/scene_palette_test.dart` measures this on the rendered scenes, `test/ui/backdrops_test.dart` on pictures.
- **One text size per reel.** A card's most quotable short sentence gets a **spotlight reel** of its own in large display type; emphasis inside a reel is colour and weight only.
- **Room around the text.** Text sits in the middle of the screen at your chosen size; text too long for one reel continues on the next.
- **Fonts fit the book.** Seven voices (classic, romance, fantasy, sci-fi, suspense, modern, playful) pair a body and a display font. The app picks one from the book's genre tags, title and opening pages; on paid plans the AI picks. **Settings → Font** can use one font for every book instead.

Screens use a light or dark theme (**Settings → Appearance**: system default, light or dark); scenes appear only while reading. On the Free plan, **Settings → On-device AI** downloads a small model (Qwen3 0.6B, 345 MB, or Gemma 4 E2B, 2 GB, via LiteRT-LM) that writes recaps, quick checks, chapter teasers and word meanings on the phone. It needs Android 11+ and the arm64 APK; its native library is fetched (SHA-256-pinned) from the `flutter_edge_ai` GitHub releases when the app is built.

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
| `GET /v1/me/export`, `DELETE /v1/me`, `GET /account/delete` | Download all your data; delete the account and everything tied to it; the deletion help page for Google Play |
| `POST /v1/activity/batch`, `POST /v1/activity/book-finished` | Reading events, re-verified server-side |
| `GET /v1/leagues/current`, `GET /v1/leaderboards/friends` | Weekly league and friends board |
| `POST /v1/social/follow/:userId`, `DELETE /v1/social/follow/:userId`, `POST /v1/social/follow-handle`, `POST /v1/social/follow-code` | Following (one way); an invite code makes both readers follow each other |
| `GET /v1/users/:id`, `GET /v1/users/:id/followers`, `GET /v1/users/:id/following` | A reader's public profile (`me`, a user id or `@handle`) and their lists |
| `GET /v1/feed?before=`, `POST /v1/activities/session`, `POST /v1/activities/:id/kudos` | The Today feed (20 at a time), reading sessions, kudos |
| `GET`/`POST /v1/activities/:id/comments`, `DELETE /v1/comments/:id` | Comments on activities |
| `POST`/`DELETE /v1/social/block/:userId`, `GET /v1/social/blocked`, `POST /v1/reports` | Blocking (both ways: no follows, profiles, feed or comments) and reports |
| `GET /v1/admin/reports`, `POST /v1/admin/reports/:id` | Report review (only with `ADMIN_TOKEN`) |
| `POST /v1/errors` | Crash reports from the app (Error Reporting events) |
| `GET /privacy`, `GET /terms` | The privacy policy and terms (from `app/assets/legal/`) |
| `GET /v1/sync?since=`, `PUT /v1/sync` | Notebook and reading-position sync |
| `POST /v1/share`, `GET /c/:id`, `GET /i/:code`, `GET /.well-known/assetlinks.json` | Share links, preview pages, invites, App Links |
| `POST /v1/book/profile` | The AI's choice of fonts for a book (paid plans) |

Configuration (all optional locally):

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | `postgres://…` for Postgres; otherwise an embedded PGlite database in `./data/pglite` |
| `ANTHROPIC_API_KEY` | Claude credentials (needed only for AI cards) |
| `FIREBASE_PROJECT_ID` | Enables Google sign-in (Firebase ID tokens); without it, accounts are per device |
| `PUBLIC_BASE_URL` | Base URL for share and invite links |
| `ANDROID_CERT_SHA256` | Signing-certificate fingerprints for Android App Links |
| `TTS_API_KEY` | Natural read-aloud voice (secret). Without it the app uses the phone's voice |
| `TTS_BASE_URL`, `TTS_MODEL` | OpenAI-compatible speech API (default `https://api.deepinfra.com/v1/openai`, `hexgrad/Kokoro-82M`) |
| `PLAY_PACKAGE_NAME` | Android package name, for Play Billing |
| `PLAY_SERVICE_ACCOUNT_JSON` | Service-account key with Play Console access, to verify purchases (secret) |
| `PLAY_RTDN_SECRET` | Secret in the Pub/Sub push URL for Play real-time notifications (secret) |
| `BILLING_ENFORCED` | `1`: serve the verified plan instead of the one the app asks for |
| `SUPPORT_EMAIL` | Shown on `/account/delete` for readers who no longer have the app |
| `MODERATION_WORDS_FILE` | Words and phrases (one per line) kept out of names, bios and comments. Links and staff-like usernames are always refused |
| `ADMIN_TOKEN` | Turns on report review (secret; sent as `x-admin-token`) |
| `TRUST_PROXY` | `1` behind a load balancer (Cloud Run), so rate limits see the reader's address |
| `NODE_ENV` | `production` on Cloud Run: requires a Postgres `DATABASE_URL` and logs in Cloud Logging's format |

Keep keys in your host's secret store (e.g. Cloud Run secrets), never in the repository. What else is needed to launch (Play Console, subscriptions, signing, Firebase) is listed in `docs/IMPLEMENTATION_PLAN.md`, "Launch checklist".

### AI direction (paid tiers)

Each chapter goes through two AI passes. The tier's model (Haiku, Sonnet or Opus) reads the chapter: where cards start, recaps and quick checks. Then Haiku art-directs every card: which phrases to stress and which short sentence deserves a spotlight reel (verified word-for-word against the text), the layout and word meanings. One more small request per book picks its fonts (`POST /v1/book/profile`; only the title, author, genre tags and about 900 words of the opening pages are sent). (The AI still names a scene per chapter, but the app no longer uses it: books open on your own pictures.)

### Your pictures and music (every plan)

**Pictures:** put JPG, PNG or WebP files in `app/assets/images/backgrounds/` and build the app (CI builds it on every push). About 1080 × 2400 pixels and under 1 MB each keeps the app small; the file name becomes the picture's name. How the text stays readable: `app/lib/ui/backdrops.dart` decodes each picture small, crops it to what the phone shows, and measures it in 11 bands down the screen. Each band is shaded just enough for body text to keep 7:1 contrast in the middle of the screen and 4.5:1 at the edges, over the brightest (or darkest) tenth of its pixels, with light text on a shade of the picture's own darkest hue or dark text on a light veil, whichever leaves more of the picture to see. `test/ui/backdrops_test.dart` checks this on bright, dark, split and busy pictures.

**Music:** put MP3, M4A, AAC, OGG, Opus, WAV or FLAC files in `app/assets/sounds/music/` and build the app. Each book starts a random track and plays on through them; previous, pause and next are at the top of the reader with the controls, and Settings → Music turns it off or sets the volume. Only add music you're allowed to use. Until you add some, the player has 9 calm loops bundled with the app (`app/assets/sounds/`, about 5.6 MB: rain, café, surf, birdsong, wind, a fire, crickets, distant city, soft noise), which repeat until skipped. Music mixes with other apps rather than pausing them, stops when the app goes to the background or another tab, and gets quieter during read-aloud.

The loops are public domain, CC0 or CC BY; sources and credits are in `app/assets/sounds/CREDITS.md` and on the app's licences page. `app/tool/build_scene_sounds.py` rebuilds them.

Plans and models (`server/src/config.ts`; prices and margins in `docs/DESIGN.md` §6):

| Plan | Price | Reads your books with |
|---|---|---|
| Free | $0 | rules on the phone |
| Lite | $3.99/mo | `claude-haiku-5-5` |
| Plus | $8.99/mo | `claude-sonnet-5-5` |
| Pro | $19.99/mo | `claude-opus-5-5` |
| Scholar | $29.99/mo | `claude-fable-5-2` (needs an API organisation with standard 30-day data retention) |

## Licenses of bundled data

Fonts (all SIL Open Font License, unmodified, licence texts in `app/assets/fonts/`): Literata, Atkinson Hyperlegible, DM Serif Display, Lora, Playfair Display, Alegreya, Cinzel, Exo 2, Orbitron, Libre Baskerville, Oswald, Outfit, Nunito and Fredoka. Sound loops: public domain, CC0 and CC BY recordings, credited in `app/assets/sounds/CREDITS.md`. Dictionary: WordNet 3.0 (WordNet License). Word frequencies: wordfreq (CC BY-SA 4.0). Starter book: *Alice's Adventures in Wonderland* (public domain). See `app/assets/lexicon/README.md`.
