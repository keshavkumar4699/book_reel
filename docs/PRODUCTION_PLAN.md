# Cloro: from working app to production

_13 Nov 2026. Written after the Cloro redesign (`docs/CLORO_PLAN.md`, steps 1–9) was finished._

## Where it stands

The app and server are feature-complete for a first release, and tested: 179 app tests and 78 server tests, with CI green on every push.

**Already production-grade:**
- Offline-first reading.
- Play Billing with server verification and real-time notifications.
- AI and speech quotas per plan.
- Contrast-tested scenes.
- A strict request schema wherever personal data goes to the server (mood, sessions).
- Migrations that only ever add.
- A `/healthz` check.

**Not yet production-grade:** found by auditing the code and listed below. Each item says what exists now, what to do, who does it, and when it counts as done.
- **🧑‍💻 in code:** I can do it in this repository.
- **🔑 your accounts:** it needs your Google/Play/Firebase/domain accounts or a decision only you can make.

---

## Phase A: must-haves before anyone outside your test group installs it

| # | Item | Now | To do | Who | Done when |
|---|---|---|---|---|---|
| A1 | **Release signing and versioning** | Release APKs are signed with the debug key (`app/android/app/build.gradle.kts`). The version is set by hand. | Create an upload key and turn on Play App Signing. Gradle reads the keystore from `key.properties`, or from CI secrets. CI builds a signed **AAB**, and the version code comes from the CI run number. | 🔑 key, 🧑‍💻 Gradle/CI | CI artifact is a signed AAB that Play Console accepts |
| A2 | **Real accounts** | Identity is a random device id sent as `x-device-id`. Anyone who learns it can act as that reader. Firebase token checking exists on the server (`FirebaseVerifier`), but the app has no sign-in. | Firebase Auth in the app: anonymous on first run, with Google sign-in to keep the account across phones. Send ID tokens, not device ids. The server already links `device:` accounts to `fb:` ones (`aliases`). Once every client sends tokens, stop accepting bare device ids. | 🔑 Firebase project, 🧑‍💻 app + server | Every request carries a verified token; switching phones keeps follows, streak and notebook |
| A3 | ✅ **Delete account and download my data** (done: `DELETE /v1/me`, `GET /v1/me/export`, `/account/delete`, Settings → You; plus an Online features switch) | Neither exists. Play requires in-app account deletion plus a web link for any app with accounts. | `DELETE /v1/me` erases the user, follows, sessions, comments, kudos, notebook sync, mood usage and shares. `GET /v1/me/export` returns a JSON archive. In Settings → You: "Download my data" and "Delete account" (with a confirm step). Add a small web page at `/account/delete` for the Play form. | 🧑‍💻 | Tests show deletion removes every row; the Play Data safety form can say "users can request deletion" |
| A4 | **Abuse protection** | Quotas cover AI and speech only. Nothing limits follows, comments or sessions per minute. There's no report or block, and no word filter on usernames, bios or comments. | Rate limits per user and IP (`@fastify/rate-limit`): comments 10 a minute, follows 30 a minute, sessions 60 an hour. **Report** for a comment, profile or activity, saved in a `reports` table. **Block**: they can't follow you, see your feed or comment, and you don't see them. A blocklist filter for usernames and bios, with suspicious comments held back. Readers who are reported repeatedly get `hidden` (already respected everywhere). | 🧑‍💻 | Tests for limits, block and report; a list of open reports exists for review |
| A5 | **Privacy policy, terms, Data safety, age rating** | Mentioned in the docs only. | Write the privacy policy and terms; I can draft them from what the app actually collects, for you or a lawyer to approve. Host them on your domain and link them from onboarding and Settings. Fill in Play's Data safety form and content rating. Ask for an age of 13+ at sign-up (the social features make it a social app). | 🔑 approval and hosting, 🧑‍💻 drafts and links | Published pages; Data safety form submitted |
| A6 | **Server hosting** | It runs locally with PGlite; Postgres is supported. There are no deployment files. | A `Dockerfile` (Node 22, `npm ci --omit=dev`, `dist/`), Cloud Run with Cloud SQL Postgres and automatic backups. Migrations run at start-up (already safe to repeat). Secrets go in Secret Manager. Add a deploy workflow (tag → build → Cloud Run) and a staging service. | 🔑 GCP project, 🧑‍💻 Docker and workflow | `https://api.<domain>/healthz` is green; app CI builds with `BOOKREEL_API` set |
| A7 | **Crash and error reporting** | None. | Sentry (or Crashlytics) in the app and the server, both off until a DSN is set. Logs as structured JSON (Fastify's logger is already on). Alerts for 5xx rate, latency, and daily AI spend over budget (the `ai_usage` table already has the costs). Uptime check on `/healthz`. | 🔑 Sentry/GCP, 🧑‍💻 hooks | A test crash shows up in the dashboard; an alert reaches you |
| A8 | **Play billing live** | Code done (Phase 8). | The `IMPLEMENTATION_PLAN.md` launch checklist, steps 4–6: products, prices, the service account and the Pub/Sub push, then `BILLING_ENFORCED=1`. | 🔑 | A test purchase, upgrade, cancel and restore work on the closed track |
| A9 | **App Links and share pages on your domain** | The server already serves `assetlinks.json`, `/c/:id` and `/i/:code`. The app has no intent filter. | Add the intent filter for `https://<domain>/c/*` and `/i/*`, and set `ANDROID_CERT_SHA256` to the Play signing key. Invite links open the app and follow the inviter. | 🔑 domain, 🧑‍💻 manifest and routing | Tapping an invite link on a phone opens Cloro |
| A10 | **Closed testing** | Testing is by APK side-load. | An internal, then closed, test track with real testers for at least 14 days. Play requires a closed test before production for new personal developer accounts; check the current tester count in Play Console. Collect crashes and feedback; fix the top issues. | 🔑 + 🧑‍💻 | Crash-free sessions ≥ 99.5%, no open P1 bugs |

## Phase B: launch quality (the first month)

| # | Item | To do | Who |
|---|---|---|---|
| B1 | **Push notifications** | FCM: kudos, comments, new followers (grouped, at most a few a day, quiet hours), and the existing streak nudges moved to the server when signed in. A **notifications inbox** (bell on Today) backed by a `notifications` table, so nothing depends on push being on. Per-kind switches in Settings. | 🔑 Firebase, 🧑‍💻 |
| B2 | **Integration tests on real devices** | `integration_test/`: onboarding → import a book → read 10 cards → save → share → follow → comment. Run it on Firebase Test Lab across low-end and recent phones on each release tag. | 🧑‍💻 (+ 🔑 Test Lab) |
| B3 | **Performance and size budget** | Targets: 60 fps scroll on a 4 GB phone, cold start under 2 s, APK under 40 MB per ABI. Today's CI artifact (all ABIs together) is about 64 MB; most of the weight is fonts, sounds and the lexicon. Subset the fonts, compress the sounds to Opus at 48 kbps, and use deferred components for rarely used voices. Add a startup trace in CI. | 🧑‍💻 |
| B4 | **Accessibility audit** | A TalkBack pass on every screen. Check large-text layouts at 200% with no clipping, and touch targets of at least 48 px (the kit already has 44–56). Respect reduced motion (scenes and swipes already do). Contrast is already tested. | 🧑‍💻 |
| B5 | **Languages** | Move the strings to ARB files (`intl` is already a dependency) and set `supportedLocales`. Start with Hindi; dates and numbers by locale. The AI already writes recaps in the book's language. | 🧑‍💻 (+ translators) |
| B6 | **Privacy-friendly product analytics** | Count retention, streak survival, cards per session, and conversion to paid. Opt-in, no book text, nothing sold. Use self-hosted PostHog or Firebase Analytics with consent mode. | 🔑 + 🧑‍💻 |
| B7 | **Remote config and kill switches** | Server flags (`/v1/config`): turn off comments, mood, Gemma, an AI tier, or ask for an update if a release breaks. | 🧑‍💻 |
| B8 | **Support and feedback** | "Send feedback" in Settings with an optional screenshot and logs, to an email or the server. Show the app version in About. | 🧑‍💻 |
| B9 | **Store listing** | Screenshots on light and dark scenes, a short video, the feature graphic and the description. A/B test the icon and first screenshot in Play Console. | 🔑 + 🧑‍💻 assets |
| B10 | **Data retention and cost control** | Prune `reading_events_seen` after 90 days, compact `ai_usage`, and cap the TTS cache size. Watch AI spend per paying user against DESIGN.md §5; the Batch API already halves background chapters. | 🧑‍💻 |

## Phase C: growth (after launch)

- **iOS** (Flutter makes this mostly packaging): App Store billing, Sign in with Apple, push.
- **Reading clubs and challenges:** a shared book, a weekly target, the group's feed.
- **Recommendations:** what readers like you finish, from genres, moods and completion. No ads.
- **Web reader** for share links (read a public-domain passage in the browser, then "continue in the app").
- **Highlights in public**, opt-in: a book's most-saved lines, public-domain books only.
- **Creator tools:** publishers upload DRM-free books with AI cuts reviewed by them.

---

## Suggested order

1. **Code-only work I can do now** (no accounts needed), each with tests:
   - A3, account deletion and data export;
   - A4, rate limits, report and block, text filters;
   - A6, the Dockerfile and deploy workflow (it runs once you add the GCP secrets);
   - A1, release-signing Gradle and CI wiring (it switches on when you add the keystore secrets);
   - A7, Sentry hooks behind a DSN;
   - B7, remote flags;
   - B8, feedback.
2. **Your accounts, in this order:**
   - Firebase project (A2, B1);
   - GCP project and domain (A6, A9);
   - Play Console app, signing and products (A1, A5, A8);
   - Sentry (A7).
3. **Then wire up** sign-in (A2), push (B1) and App Links (A9).
4. **Closed testing** for 14 days (A10), working through B2–B5 alongside.
5. **Production release**, then Phase B's remaining items and Phase C.
