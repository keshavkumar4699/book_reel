# BookReel — Product & Technical Design Document

| | |
|---|---|
| **Product** | BookReel (working name): read EPUB / text PDF books as a vertical feed of short "reel" cards |
| **Platform** | Android first (Flutter, so iOS is possible later) |
| **Status** | Draft v1.1 |
| **Date** | 2026-11-09 |
| **UX/UI guidelines** | [`UX_DESIGN.md`](./UX_DESIGN.md) (takes priority over this file for interaction & visual design) |

---

## 1. Summary

Many people find it hard to sit down with a 300-page book, but they will happily scroll short-form video for an hour. BookReel takes the scrolling habit and points it at books. A user imports an EPUB or a text-based PDF. AI cuts the book into **reel cards**: short passages in the author's own words. Each card is long enough to keep its meaning and short enough to read in 20–60 seconds. Users swipe through the book, and the app tracks **streaks**. Users can **compete with friends** (similar to Strava), save cards, highlight key points, look up hard words, and **share a card or their progress** to social media in one tap.

### 1.1 Goals
1. Make finishing books feel like scrolling a feed, while still being real reading.
2. Cut books at the right places: never mid-thought, never so short that context is lost.
3. Build daily habits with streaks, goals and social competition.
4. Make sharing cards and progress the easiest action in the app (≤ 2 taps).
5. Offer a useful free tier on free AI models, with better AI quality on each paid tier, and keep healthy margins on every tier.

### 1.2 Non-goals (v1)
- Scanned or image-only PDFs (OCR). Only PDFs with a text layer are supported. Scanned PDFs are detected and rejected with a clear message.
- DRM-protected books (Kindle, Adobe DRM). Only DRM-free files are supported.
- A bookstore or selling books. Public-domain books may be offered as a starter library.
- AI rewriting of books. **Cards always show the author's original text.** AI only decides where to cut and adds extras (title, hook, highlights, word meanings).

### 1.3 Target users
| Persona | Need |
|---|---|
| "Lapsed reader" (18–30) | Wants to read again but loses focus; already scrolls reels daily |
| "Self-improvement reader" | Reads non-fiction; wants key points, highlights and shareable quotes |
| "Competitive habit builder" | Uses Strava/Duolingo; motivated by streaks, leaderboards, badges |
| Student | Needs hard-word help, highlights and exportable notes |

---

## 2. Feature Specification

### 2.1 Library & import (basic reading-app features)
- Import from device storage, the Android share sheet ("Open with BookReel"), or a URL (DRM-free files only).
- Supported formats: **EPUB 2/3** and **PDF with a text layer**. PDFs are checked for a text layer on import. If more than 20% of pages have no extractable text, the file is rejected as "scanned".
- Library grid/list showing cover, title, author, % progress, reels left and estimated time left.
- Sort and filter by recently read, progress, title, author or tag. Users can make shelves and collections.
- A starter library of public-domain classics (Project Gutenberg / Standard Ebooks), already processed, so new users can start immediately.
- Duplicate detection by file content hash (SHA-256).

### 2.2 Reel reader (core experience)
Each book becomes a vertical feed of cards. Each card holds one segment of the book.

**Card anatomy**
```
┌──────────────────────────────┐
│ Ch. 3 · The Habit Loop  12/48│  ← chapter + position in chapter
│ ▓▓▓▓▓▓▓░░░░░░░░░░ 24% book   │  ← book progress bar
│                              │
│  "Why cravings beat willpower"│ ← AI hook title (optional, toggle)
│                              │
│  The author's original text, │
│  60–180 words, with AI key   │
│  points softly highlighted   │
│  and hard words underlined.  │
│                              │
│                              │
│   ♡     ✎     🔖     ⤴    ⋯  │ ← bottom action row (fades while reading)
└──────────────────────────────┘
```

> **Current reel design (UX_DESIGN.md, Revision 4).** The sketch above is the original v1 card. A reel today is full-screen over a calm scene: the author's words in one comfortable size, a phrase per line, in the middle of the screen with space above and below; colours come from the scene (≥ 7:1 contrast for text); fonts come from the book (a body and a display face per genre "voice"). The card's most quotable short sentence can get a **spotlight reel** of its own in large display type, and text too long for one screen **continues on the next reel**. Likes, saves and notes belong to the reel on screen; a card shown as several reels counts once towards the daily goal.

**Reels-style interactions**
| Gesture | Action |
|---|---|
| Swipe up / down | Next / previous card |
| Swipe left / right | Next / previous chapter (with a chapter title card in between) |
| Double-tap | "Like" the card, which adds it to Liked (heart animation) |
| Long-press a word | Word meaning sheet |
| Long-press and drag | Select text to highlight or add a note |
| Tap the share icon | One-tap share sheet (see 2.6) |
| Tap the save icon | Save to collection (see 2.8) |
| Pinch | Change font size |
| Tap the top bar | Show table of contents / chapter scrubber |

**Other reels features:** a continuous feed within a book, split into **sessions** with a segmented daily-goal bar and a designed "Session complete" ending (see UX_DESIGN.md §5.3); a "Review" feed of saved/liked cards and words for spaced review, auto-advance mode (scrolls at the user's measured reading speed, can be paused), **scene sounds** (each scene has its own ambient sound: rain on the window, café murmur, waves, wind in the pines; on by default for every tier, one tap on the speaker mutes it so readers can play their own music), haptic feedback on swipes and milestones.

**Special card types** inserted by the pipeline:
- **Chapter title card**: chapter name, estimated reels and minutes, optional AI one-line teaser.
- **Recap card**: every ~10 cards and at the end of each chapter, 2–3 AI bullet points summarising what was just read (clearly marked as AI-written).
- **"Previously…" strip**: a one-line context reminder shown on cards that depend on earlier text when the user returns after a break of more than 24 h.
- **Milestone card**: "You finished Part 1 🎉" with a one-tap share.
- **Recall card** (optional, every ~10 cards): one-tap "what was the main idea?" check, with no penalty (testing effect).
- **Reflect card** (optional, chapter end): "One idea you'll try this week?", saved to the Notebook.

### 2.3 Classic reading mode (basic reading-app features)
Some readers will want normal paging sometimes. A toggle switches between **Reel mode** and **Page mode** at the same position. Both modes share the same position model (sentence ID), so the reading position is never lost.

Must-have reader features:
- Themes: light, dark, sepia, AMOLED black; custom background colour.
- Typography: font family (including a dyslexia-friendly font), size, line height, margins, justification.
- Table of contents, chapter scrubber, go to %.
- Full-text search inside a book.
- Bookmarks, highlights (4 colours), notes.
- Letter- and word-spacing controls (these help dyslexic readers more than special fonts).
- Text-to-speech using Android TTS: plays the current card and auto-advances. Sentence highlighting during playback.
- Brightness control and a "keep screen on" setting.
- Offline reading; processed books are fully cached.
- Multi-device sync of progress, highlights, notes and saved cards (signed-in users).
- Export highlights and notes to Markdown / PDF / plain text.
- Accessibility: TalkBack labels, scalable text, high-contrast theme, reduced-motion option.

### 2.4 Smart segmentation (AI card generation)
The key product feature. Full pipeline in §4. Product rules:
- Default target length is **~120 words** (about 30–45 s at average reading speed). The user can choose **Bite (60–90)**, **Standard (90–150)** or **Deep (150–220)** in settings.
- **Never** cut mid-sentence. **Never** split a dialogue exchange, a list, a quote block, a worked example or an argument's claim from its immediate support.
- Prefer cutting at topic shifts, scene changes, time jumps and speaker changes.
- Each card is labelled `standalone` or `needs_context`. This label drives the "Previously…" strip and whether the card can be shared without extra context.
- Cards are generated **just in time**: the chapter being read plus the next 1–2 chapters are processed first, and the rest of the book is processed in the background. The user can start reading within seconds of importing.

### 2.5 Hard-word meanings
- **Detection (on device, free):** a word is "hard" if its Zipf frequency is below a threshold that adapts to the user's level (beginner / intermediate / advanced, auto-tuned from how often they tap words). Proper nouns are excluded.
- Hard words get a subtle dotted underline, which can be toggled.
- Tapping any word, hard or not, opens a bottom sheet with:
  1. **Dictionary definition**: offline, bundled open dictionary (WordNet, with optional Wiktionary-derived data), part of speech, pronunciation (Android TTS).
  2. **"In this sentence" meaning**: AI explains the word in its actual context, e.g. "*sanguine* here means hopeful, not blood-related". Paid tiers get this pre-generated by the pipeline. The free tier generates it on demand with the on-device model, or a cheap cloud call with a daily cap.
  3. Translation into the user's native language (optional, on-device translation).
  4. **Add to Word List**: words go into a spaced-repetition deck. Review cards appear in the For You feed.

### 2.6 Sharing (must be super easy)
The rule: **any card or any progress stat can be shared in ≤ 2 taps.**

**Share a card**
1. Tap ⤴ on a card. A bottom sheet opens with a **live preview** already rendered and a row of direct targets: Instagram Story, WhatsApp, WhatsApp Status, X, Facebook, Telegram, Snapchat, Save image, Copy link, More…
2. Tap a target. Done.

Optional extras in the sheet: switch template (Quote, Minimal, Book-cover background, Gradient, Dark), aspect ratio (9:16 story, 4:5 feed, 1:1), choose which sentences to include (default: highlighted sentences, or the whole card if short).

Every shared image includes book title, author, a small BookReel watermark and a **deep link / QR code** (`https://bookreel.app/c/{shareId}`). The link opens the card in the app if installed, otherwise a web preview page with an install button.

**Share progress (Strava-style)**
- Auto-generated images: "Finished *Atomic Habits* in 9 days · 412 reels · 6 h 40 m", streak milestones (7/30/100/365 days), weekly recap, monthly challenge badge, Year in Review.
- After a milestone a celebration screen shows with a **Share** button already focused.
- Sharing a progress card to a story counts toward a "Spread the word" badge.

**Copyright safeguard:** for copyrighted books, shared card text is limited to **≤ 75 words per share**, always with attribution (a short quotation with credit). Public-domain books have no limit. The limit is configurable server-side.

### 2.7 Highlights & key points
- **AI key points:** the pipeline marks 0–2 key sentences per card. They are shown with a soft highlight (toggle: Off / Subtle / Bold).
- **User highlights:** long-press-drag or double-tap a sentence (configurable), 4 colours, optional note.
- **Highlights view** per book and across all books, filterable by colour and tag. Each highlight jumps back to its card.
- **Key Points summary** per chapter: AI key points + user highlights merged into a one-screen chapter summary.
- Export to Markdown / PDF / Notion-style text; share a highlight as an image (same flow as 2.6).

### 2.8 Saved cards
- 🔖 saves a card to **Saved** (default) or to a user-made collection ("Quotes", "Ideas for work"…).
- Saved cards are stored with their full text, so they work offline and survive book deletion.
- **Saved feed:** swipe through saved cards across all books in reel format.
- Liked (double-tap) is separate from Saved: Liked trains the For You feed, Saved is the user's own archive.

### 2.9 Streaks, goals & competition (Strava-like)

**Verified reading activity**
A card counts as **read** only if the dwell time is at least `0.35 × expected_time`, where `expected_time = words / user_wpm`. The user's WPM is learned from their own history, clamped to 120–600. This stops speed-scrolling from counting. Cards scrolled past too quickly are counted as "skimmed": progress is saved, but they don't count toward goals or leaderboards.

**Daily goal & streak**
- Daily goal options: 5 / 10 / 20 / 40 verified cards, or 5 / 15 / 30 minutes. Default: 10 cards. Alternative **weekly goal** mode (e.g. 5 of 7 days) for users who find daily streaks stressful.
- The streak goes up by one each local day the goal is met. Uses the user's time zone; a change of time zone is handled without losing the streak.
- **Streak freeze:** 1 per week on Free, 3 on paid tiers. Freezes are used automatically on a missed day.
- One reminder at the user's chosen time, worded around the habit they named in onboarding ("After your morning tea…"). A calm "streak at risk" nudge at 8 pm only if they haven't read yet. No reminders during quiet hours (22:00–08:00). All can be turned off.

**Competition**
| Feature | Description |
|---|---|
| Friends | Follow users, contact discovery (opt-in), invite link |
| Activity feed | "Asha read 32 reels of *Sapiens* · 41 min" with **Kudos** 👏 and comments. Social notifications are grouped into one daily digest |
| Leaderboards | Default: **Friends** and weekly **Leagues** of ~24 similar readers (top 5 move up). Ranked by verified active days and minutes. City/Country/Global and per-book boards are opt-in. Users can hide all comparisons |
| Clubs | Groups (book club, college, office) with their own leaderboards and a shared current book |
| Challenges | Monthly ("Read 1,000 reels in December"), book challenges ("Finish *1984* in 21 days"), club challenges |
| Book segments | The Strava "segment" idea: per-chapter leaderboards ranked by **consistency** (days active), not speed, so skimming isn't rewarded |
| Badges & levels | XP from verified reading; levels; badges (First book, 7-day streak, Night owl, 10 books, Vocabulary 100…) |
| Year in Review | Shareable yearly summary |

**Fair play**
- Leaderboards only count verified minutes, capped at 4 h/day.
- Server-side anomaly detection: implausible WPM, identical dwell patterns, emulators, time-zone abuse. Flagged accounts are hidden from public boards until reviewed.
- Privacy: profile and activity visibility can be Public, Friends or Private. Leaderboards are opt-in for minors.

### 2.10 Onboarding
1. Choose 3 interests → a processed starter book opens **immediately** (first card in under 60 s).
2. The first 3 cards are the tutorial (swipe, long-press word, share), and they count toward day 1's goal.
3. After those cards: set the daily goal and the habit anchor ("After I ___, I'll read"), then the reminder time, then ask for notification permission (explaining why first).
4. Optional sign-in (Google), offered when saving or adding friends. The app can be used without an account. Accounts are needed for sync, social features and paid AI tiers.

### 2.11 Settings
Reading (card length, AI hook titles on/off, key-point highlight style, hard-word underline, font/theme), Goals & reminders, Privacy & social, AI model tier and usage meter, Storage (cache size, offline books), Account & subscription, Data export & delete account.

---

## 3. System Architecture

### 3.1 Overview
```
┌────────────────────────── Android app (Flutter) ──────────────────────────┐
│ UI (Reel feed, Page mode, Library, Social, Share)                         │
│ State: Riverpod      Routing: go_router      Local DB: Drift (SQLite)     │
│ Parsers: EPUB (zip+XHTML), PDF (PDFium)   Sentence splitter               │
│ On-device AI: rules segmenter + small open-weight LLM (Free tier)         │
│ Offline dictionary (WordNet, SQLite)   Card renderer (share images)       │
└───────────────┬───────────────────────────────────────────────────────────┘
                │ HTTPS (Firebase Auth ID token)
┌───────────────▼──────────────── Backend (GCP) ────────────────────────────┐
│ API service (Cloud Run)  ── REST/JSON                                     │
│ Segmentation workers (Cloud Run jobs, Pub/Sub queue)                      │
│      └─► Claude API (Haiku 5.5 / Sonnet 5.5 / Opus 5.5), Batch API        │
│ Postgres (Cloud SQL): users, books, cards, highlights, social, billing   │
│ Redis (Memorystore): leaderboards (sorted sets), rate limits, quotas     │
│ Cloud Storage: processed segment maps, share images, web previews        │
│ FCM: notifications     Play Billing RTDN → billing service                │
│ Share web page (Cloud Run + CDN): bookreel.app/c/{id} previews            │
└───────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Flutter app — key choices
| Concern | Choice | Notes |
|---|---|---|
| State management | Riverpod | Testable, works well with async data |
| Navigation | go_router | Handles deep links for shared cards |
| Local DB | Drift (SQLite) | Relational data (books, cards, highlights), FTS5 for search |
| Feed | `PageView.builder` (vertical) with preloading ±3 cards | Keep each card widget simple to hold 60/120 fps |
| EPUB parsing | Unzip + parse OPF/NCX/nav + XHTML → own block model | Evaluate `epubx`; own parser likely needed for fine control |
| PDF text | PDFium-based (e.g. `pdfrx`) | Text extraction plus layout heuristics: header/footer removal, de-hyphenation, column order |
| Sentence splitting | Rule-based splitter (abbreviations list, quotes, ellipses) on device | Gives stable sentence IDs |
| On-device LLM | Small open-weight model (Gemma-class, 1–2B, 4-bit) via MediaPipe LLM Inference / `flutter_gemma` | Optional ~0.6–1.5 GB download; only on devices with ≥ 6 GB RAM |
| TTS | `flutter_tts` (Android TTS engine) | |
| Share | `share_plus` + Instagram Stories intent via a small platform channel | Images rendered with `RepaintBoundary.toImage` at 1080×1920 |
| Deep links | Android App Links (own domain) | Do not use Firebase Dynamic Links (shut down 2025) |
| Billing | `in_app_purchase` (Google Play Billing) | Server-side verification required |
| Notifications | FCM + local notifications | |
| Analytics / crashes | Firebase Analytics + Crashlytics | |

### 3.3 Book content model (shared by app and backend)
```
Book (id, content_hash, title, author, lang, format, is_public_domain)
 └─ Chapter (idx, title, toc_level)
     └─ Block (idx, type: paragraph | heading | quote | list | dialogue | code | table | image)
         └─ Sentence (sid = "c{ch}.b{blk}.s{n}", text, char_start, char_end)

SegmentMap (book_content_hash, segmenter_version, model_tier, card_len_pref)
 └─ Card (idx, chapter_idx, start_sid, end_sid, word_count,
          title?, hook?, type, standalone: bool,
          key_sids[], hard_words[{word, sid, meaning_in_context}],
          recap_after?: [bullets])
```
- **Sentence IDs are the single position model.** Reading position, highlights, notes, saved cards and sync all point to sentence IDs. Changing card length or re-segmenting a book never loses the user's place.
- The **segment map** only stores IDs and AI extras, not the book text. The text stays on the user's device and is joined with the map locally.

### 3.4 Data privacy & copyright approach
- On the Free tier with on-device AI, the book **never leaves the device**.
- On cloud AI tiers, chapter text is sent to the backend → Claude API for processing. The backend does not store the book text after processing (only transient queue payloads with a 24 h TTL). Anthropic commercial API terms apply; confirm the retention and training settings before launch and publish them in the privacy policy.
- **Segment-map cache keyed by content hash:** if two users import the same file, the second user reuses the first user's segment map (IDs and AI extras only). This is a large cost saving for popular books (see §5) and shares no book text between users.
- Shared cards are limited to short quotations with attribution (§2.6).

### 3.5 Backend services
| Service | Responsibility |
|---|---|
| `api` | Auth (Firebase ID tokens), books metadata, sync, highlights, saved, social graph, feed, share links |
| `segmenter` | Queue consumer: runs the AI pipeline per chapter, validates, writes segment maps |
| `quota` | Per-user AI credits per billing period; per-tier model routing |
| `activity` | Ingests reading events, verifies dwell, updates streaks, XP, leaderboards |
| `billing` | Play Billing purchase verification, Real-Time Developer Notifications, entitlement updates |
| `share-web` | Server-rendered preview pages and Open Graph images for share links |
| `notifier` | Streak reminders, kudos, challenge updates (FCM) |

### 3.6 Core API (REST, JSON)
```
POST   /v1/books                       {content_hash, metadata, toc}      → book_id, cached_map?: bool
POST   /v1/books/{id}/segment          {chapters:[{idx, sentences:[{sid,text}]}], priority: "now"|"background"}
GET    /v1/books/{id}/segments?from_ch=&to_ch=&tier=&len=                  → cards[]
POST   /v1/activity/batch              [{card_id, book_id, dwell_ms, words, ts, client_wpm}]
GET    /v1/me/streak                   → {current, best, freezes_left, today_progress}
GET    /v1/leaderboards/{scope}/{period}?metric=minutes|cards|streak
POST   /v1/social/follow/{user_id} · POST /v1/activities/{id}/kudos
POST   /v1/share                       {type: card|progress, payload}       → {share_id, url, image_url}
GET/PUT /v1/sync/{highlights|notes|saved|positions}?since=
POST   /v1/billing/verify              {purchase_token, product_id}
GET    /v1/me/ai-usage                 → {tier, books_used, books_limit, resets_at}
POST   /v1/book/profile                {tier, book, subjects[], sample}     → {voice, genre, source}         (paid)
```
`/v1/book/profile` receives only the title, author, genre tags and about 900 words of the opening pages, once per book.

---

## 4. AI Segmentation Pipeline ("perfect cut")

### 4.1 Design principles
1. **The model chooses cut points; it does not rewrite text.** The model returns sentence IDs, not passages. This keeps the author's words intact, removes the risk of made-up text in the reading view, and cuts output tokens (and cost) by about 10×.
2. **Hard rules in code, judgement in the model.** Code enforces length bounds, sentence integrity and full coverage. The model handles meaning: topic shifts, argument structure, scene changes.
3. **Chapter-sized windows.** Each request is one chapter (or about 12k tokens of one), with a small overlap of the previous chapter's ending for context. This makes just-in-time processing possible and keeps Haiku requests under its 100K-token price threshold.
4. **Validate, auto-repair, then retry once.** The model's output is never trusted blindly.

### 4.2 Stages
```
[Device] Parse → blocks → sentences (stable sIDs) → rule pre-segmentation (candidate cut points + scores)
   │
   ├─ Free tier: on-device LLM refines candidates  ─┐
   └─ Paid tiers: upload chapter → queue ─► Claude ─┤
                                                    ▼
                       Validator & repairer (code) → SegmentMap → device cache
```

**Stage 1 — Rule pre-segmentation (on device, every tier)**
Scores every sentence boundary from 0 to 1 as a candidate cut:
- +0.5 paragraph boundary, +0.4 heading or scene break (`***`, extra spacing), +0.2 discourse markers at the start of the next paragraph ("However," "Meanwhile," "In contrast"…)
- −1.0 inside a quote, list or dialogue run; −0.6 if the next sentence starts with an anaphoric reference ("This", "That", "These", "He said") that refers back
- A dynamic-programming pass picks cuts that maximise total boundary score with each card's word count kept inside the user's length band.

This alone gives acceptable cards. It is the fallback when AI is unavailable and the starting point the AI improves.

**Stage 2 — AI refinement**
Input per request:
- Cached system prompt with segmentation rules and examples (prompt caching; ~3k tokens).
- Book context: title, author, genre (fiction / non-fiction / textbook), user's length band.
- The previous chapter's last ~300 words (context only).
- The chapter as numbered sentences grouped by block: `[c03.b012.s04] Sentence text…`
- Stage 1 candidate cuts (as hints).

Output: structured JSON (Claude structured outputs, `output_config.format` with a JSON schema):
```json
{
  "cards": [
    {
      "start_sid": "c03.b001.s01",
      "end_sid": "c03.b003.s02",
      "title": "Why cravings beat willpower",
      "hook": "Your brain wants the reward, not the habit.",
      "type": "argument",            // narrative|argument|example|dialogue|definition|description|summary
      "standalone": true,
      "key_sids": ["c03.b002.s03"],
      "hard_words": [{"word": "salient", "sid": "c03.b002.s01", "meaning": "most noticeable or important here"}]
    }
  ],
  "recaps": [{"after_card": 9, "bullets": ["…", "…"]}],
  "chapter_teaser": "…"
}
```

**Stage 3 — Validator & repairer (code)**
- Coverage: every sentence belongs to exactly one card, cards are contiguous and in order. Gaps are attached to the neighbouring card; overlaps are trimmed.
- Length: a card under the minimum is merged with the neighbour that has the weaker boundary; a card over the maximum is split at the best Stage 1 boundary inside it.
- IDs: unknown or made-up sIDs mean the response is rejected.
- Extras: titles ≤ 8 words, hooks ≤ 14 words, `key_sids` must be inside the card, `hard_words` must actually appear in the referenced sentence.
- If more than 20% of cards need repair → retry once at the same tier → otherwise fall back to the Stage 1 result and mark it for re-processing.

### 4.3 Model routing by tier (v2: two passes)
Each chapter goes through two AI passes (`server/src/segmentation`):
1. **Structure & direction** on the tier's model: where each card starts, recaps, quick checks, the chapter teaser, and the chapter's **scene** (and up to 3 scene changes). The scene sets both the picture and its ambient sound.
2. **Art direction** per card on the fast model, in batches of 60 cards: 0–3 **emphasis** phrases, the **layout** (centred / left / staggered), key sentences and hard-word meanings. At most one phrase per card is a **spotlight** (level 3): it must sit in a complete sentence of 3–18 words, which the app shows on a reel of its own; the others are stressed inline. Every phrase must appear verbatim in its sentence or it is dropped.

One more tiny step runs on the fast model:
- The **book designer** picks the book's typographic **voice** (classic, romance, fantasy, sci-fi, suspense, modern or playful: a body and a display font each) from its title, genre tags and opening pages. One request per book, cached by content hash; the app's on-device rules are the fallback and the free-tier choice.

| Tier | Pass 1: structure & direction | Pass 2: art direction | Book designer |
|---|---|---|---|
| **Free** | Rules on device | Rules on device (a short key sentence is stressed, or gets a spotlight reel) | Rules on device |
| **Plus** | `claude-haiku-5-5`, effort `low` | `claude-haiku-5-5`, `low` | `claude-haiku-5-5` |
| **Pro** | `claude-sonnet-5-5`, effort `medium` | `claude-haiku-5-5`, `low` | `claude-haiku-5-5` |
| **Scholar** | `claude-opus-5-5`, effort `medium` (`high` for dense non-fiction) | `claude-haiku-5-5`, `low` | `claude-haiku-5-5` |

Why art direction runs on the fast model for every tier: it is a light task (marking phrases), but it is most of the output tokens, because it runs on every card. Running it on Sonnet would multiply the cost of a Pro book by about 3 for little visible gain. The premium models are spent where they matter: understanding the book (cuts, recaps, scenes).

Implementation notes (Claude API):
- **Adaptive thinking** (the default) with `output_config.effort` per tier, structured JSON output (`output_config.format`), and **streaming** with a 64k output budget so long chapters of short cards never truncate.
- **Prompt caching** for both fixed system prompts.
- **Just-in-time chapters** run in real time. **Background chapters** run pass 1 through the **Message Batches API (50% cheaper)**; pass 2 follows in real time.
- Keep each Haiku request **under 100K input tokens**; larger prompts cost more on Haiku 5.5.
- Handle `stop_reason: "refusal"`. Sonnet 5.5 / Opus 5.5 use the server-side `fallbacks: "default"` option. A Haiku pass-1 refusal is retried once on Sonnet, then the chapter keeps rule cards. A pass-2 refusal just leaves those cards plain.
- Pin model IDs in config (`server/src/config.ts`) so model upgrades are deliberate and evaluated.

### 4.4 Quality evaluation
- **Gold set:** 40 books (fiction, non-fiction, textbooks, poetry-heavy, dialogue-heavy, translated works) with human-labelled "good cut" boundaries, 3 annotators each.
- **Metrics:** boundary F1 (±1 sentence tolerance), % cards inside the length band, % cards rated "makes sense alone" by human raters, key-point precision, hard-word usefulness.
- **Gate:** a new prompt or model version ships only if it is no worse on any metric and better on at least one. Re-run on every change to prompts or models.
- **In-app signals:** "This cut feels wrong" option in the ⋯ menu, rate of backward swipes right after a card (a sign the card lacked context), completion rate per card type.

---

## 5. AI Cost Model

### 5.1 Claude API prices used (per 1M tokens, Anthropic first-party, as of Oct 2026)
| Model | Input | Output | Notes |
|---|---|---|---|
| Claude Haiku 5.5 | $0.10 | $0.50 | Prompts ≤ 100K tokens ($0.50 / $2.50 above) |
| Claude Sonnet 5.5 | $2.00 | $10.00 | Cache reads $0.20 |
| Claude Opus 5.5 | $4.00 | $20.00 | Cache reads $0.20 |
| Batch API | 50% off the above | | Used for pass 1 of background chapters |

Re-check prices on Anthropic's pricing page before launch.

### 5.2 Cost per book (v2 estimate)
Assumptions: an average book is ~100k words ≈ **135k input tokens**. With snack cards (~30 words each) that is **≈ 3,300 cards**.
- **Pass 1** returns only where cards start (~10 tokens per card ≈ 33k) plus recaps, quick checks, teasers and scenes (~10k), plus thinking (~20% on Haiku `low`, ~50% on Sonnet/Opus `medium`).
- **Pass 2** returns ~37 tokens of art direction per card (≈ 122k) plus thinking (~20%), on Haiku for every tier. (Removing the AI music in Nov 2026 dropped card moods and music cues: about 8 fewer tokens per card, and no music supervisor.)
- **Scene sounds** are bundled with the app (about 5.6 MB), so they cost nothing to run.
- The **book designer** is one request of about 1.5k input tokens per book: well under $0.001, so it does not change the totals below.

| | Pass 1 (tier model) | Pass 2 (Haiku) | **Per book, real time** | **Per book, typical** (70% of pass 1 via Batch) |
|---|---|---|---|---|
| Plus | Haiku ≈ $0.04 | ≈ $0.09 | **≈ $0.13** | **≈ $0.12** |
| Pro | Sonnet ≈ $0.92 | ≈ $0.09 | **≈ $1.01** | **≈ $0.69** |
| Scholar | Opus ≈ $1.85 | ≈ $0.09 | **≈ $1.94** | **≈ $1.29** |

For comparison, v1 (one pass, ~120-word cards, no art direction) cost ≈ $0.02 / $0.47 / $1.04 per book. Short cards with art direction on every card cost more, which is why v2 lowers quotas and raises prices (§6).

**Real usage costs much less than these worst cases:**
- Books are processed just in time, so abandoned books are never fully processed.
- Background chapters use the Batch API.
- The content-hash cache processes popular books once per tier and card length, then reuses them for everyone.

Planning number: expected ≈ 40% of the worst case. Validate in a pilot with real token counts (`usage` logging is built in: `ai_usage` table).

### 5.3 Infrastructure cost (rough, at 50k MAU)
Cloud Run + Cloud SQL + Storage + CDN ≈ $600–1,200/month → **≈ $0.02/MAU**. No audio streaming: scene sounds ship inside the app.

### 5.4 Cheaper model options (researched Nov 2026)
Cost per book if **both passes** ran on one model, using this section's token profile (about 0.35M input and 0.2M output tokens per book, including some thinking). Prices are per million tokens (input / output) from the providers' published rates or price trackers in Nov 2026; trackers disagree in places, so re-check before switching.

| Model | Price (in / out) | ≈ Per book | Notes |
|---|---|---|---|
| **Claude Haiku 5.5** (current Plus, and pass 2 for all) | $0.10 / $0.50 | **$0.13** (≈ $0.07 via Batch) | Already wired in; structured outputs; prompt caching |
| Claude Sonnet 5.5 | $2 / $10 | $2.70 | Pro pass 1 today (≈ $0.92 for pass 1 alone) |
| Claude Opus 5.5 | $4 / $20 | $5.40 | Scholar pass 1 today (≈ $1.85 for pass 1 alone) |
| Gemini 2.5 Flash-Lite | $0.10 / $0.40 | $0.12 | Older generation; the 3.x Flash-Lite models cost $0.25–0.30 / $1.50–2.50 |
| OpenAI GPT-5 nano | $0.05 / $0.40 | $0.10 | Newer nano tiers are listed at $0.20–0.25 / $1.25–1.50 |
| DeepSeek V4-Flash | $0.14 / $0.28 | $0.11 | Served from China: check the privacy policy and user expectations |
| gpt-oss-20b / 120b (open weights, e.g. Together, Groq) | $0.05 / $0.20 · $0.15 / $0.60 | $0.06 · $0.17 | Several hosts; quality on long chapters unproven |
| Mistral Small 4 | $0.10–0.15 / $0.30–0.60 | $0.10–0.17 | Trackers disagree on price |
| On-device model (e.g. Gemma via LiteRT) | $0 | $0 | Free tier only: a download of several hundred MB or more, newer phones, weaker at strict JSON |

What this means:
- **Claude Haiku 5.5 is already in the cheapest group.** The cheapest alternatives save at most a few cents per book, and switching costs engineering time (a second provider, different structured-output rules) and quality risk. Reasoning models can also bill many hidden thinking tokens, so real costs need a pilot.
- **The big lever is the model behind Pro and Scholar.** Pro's pass 1 on Sonnet is ~90% of a Pro book's cost. Moving Pro to Haiku would cut a Pro book from ≈ $1.01 to ≈ $0.13; moving Scholar from Opus to Sonnet would cut it from ≈ $1.94 to ≈ $1.01. The trade-off is reading quality, which the gold-set evaluation (Phase 9) should measure before deciding.
- **Free levers already in place:** Batch API for background chapters (half price), prompt caching, low effort on Haiku, shorter outputs.

---

## 6. Pricing

Principles:
- The free tier is genuinely useful: on-device cards, calm reels with rule-based emphasis and book fonts, and every scene.
- Paid tiers add the AI's direction (emphasis, spotlight lines, Auto scenes, book fonts) and better models up the ladder.
- Quotas count **"AI books" per month**. A book counts once its first AI chapter is processed; re-reading and cached books are free.
- Every tier keeps a positive margin even in the **absolute worst case** (every quota book fully processed in real time).

Google Play keeps **15%** of subscription revenue.

### 6.1 Tiers (v2)
| | **Free** | **Plus** | **Pro** ⭐ | **Scholar** |
|---|---|---|---|---|
| Price (US) | $0 | **$3.99/mo** · $29.99/yr | **$8.99/mo** · $69.99/yr | **$19.99/mo** · $159.99/yr |
| Price (India, regional) | ₹0 | **₹149/mo** · ₹1,199/yr | **₹399/mo** · ₹3,199/yr | **₹899/mo** · ₹7,199/yr |
| Reading the book (cuts, recaps, scenes) | Rules on device | Claude Haiku 5.5 | Claude Sonnet 5.5 | Claude Opus 5.5 |
| Emphasis and spotlight lines | Rule-based | AI art direction on every card | AI art direction | AI art direction |
| Fonts that fit the book | On-device rules (genre tags, title, opening pages) | Chosen by the AI | Chosen by the AI | Chosen by the AI |
| Scenes | Pick any of 8 | + **Auto**: AI picks the scene per chapter | + Auto | + Auto |
| Scene sounds (rain, café, waves…; mute to play your own music) | ✓ | ✓ | ✓ | ✓ |
| AI books / month | Unlimited (on device) | 12 (India 8) | 6 (India 4) | 6 (India 4) |
| Recap & quick-check cards | Rule-based quick checks | ✓ | ✓ | ✓ |
| Word meanings | Offline dictionary + 10 AI/day | Unlimited, in context | Unlimited, in context | Unlimited, in context |
| Streaks, goals, friends, leaderboards | ✓ | ✓ | ✓ | ✓ |
| Streak freezes / week | 1 | 3 | 3 | 5 |
| Cloud sync | Progress only | Full | Full | Full |
| Ads | Small banner in Library only, **never in the reel feed** | None | None | None |
| Free trial | — | 7 days | 7 days | 7 days |

### 6.2 Margin check (per subscriber per month)
US prices, net after the Play fee: Plus $3.39, Pro $7.64, Scholar $16.99.

| Tier | Absolute worst (all real time) | Typical worst (Batch for background) | Expected (~40%) | **Expected margin** |
|---|---|---|---|---|
| Plus | 12 × $0.13 = $1.56 (margin 54%) | 12 × $0.12 = $1.44 (58%) | $0.58 | **≈ 83%** |
| Pro | 6 × $1.01 = $6.06 (margin 21%) | 6 × $0.69 = $4.14 (46%) | $1.66 | **≈ 78%** |
| Scholar | 6 × $1.94 = $11.64 (margin 31%) | 6 × $1.29 = $7.74 (54%) | $3.10 | **≈ 82%** |

India (net after the fee at ₹88/$): Plus $1.44, Pro $3.85, Scholar $8.68. With India quotas (8 / 4 / 4) the typical-worst margins are 33% / 28% / 41% and the expected margins about 73% / 71% / 76%. Quotas and prices are set by region on the server (`server/src/config.ts`), so they can be tuned after the pilot without an app update.

### 6.3 Other revenue (later)
- One-time "AI book pack" purchases: process 1 extra book with Sonnet/Opus, ₹49 / $0.99.
- Clubs for schools and companies (team plan with admin dashboard).
- No selling of user data. No ads inside the reading experience on any tier.

---

## 7. Data Model (Postgres, main tables)
```sql
users(id, firebase_uid, handle, display_name, avatar_url, tz, reading_level, wpm,
      privacy, tier, region, created_at)
books(id, content_hash UNIQUE, title, author, lang, format, is_public_domain, word_count)
user_books(user_id, book_id, added_at, position_sid, progress_pct, status, last_read_at)
segment_maps(id, content_hash, segmenter_version, model_tier, len_pref, chapter_idx,
             storage_uri, created_at, UNIQUE(content_hash, segmenter_version, model_tier, len_pref, chapter_idx))
highlights(id, user_id, book_id, start_sid, start_off, end_sid, end_off, color, note, source: user|ai, created_at)
saved_cards(id, user_id, book_id, card_ref, text_snapshot, collection_id, created_at)
collections(id, user_id, name)
word_list(user_id, word, book_id, sid, meaning, srs_due_at, srs_interval, srs_ease)
reading_events(user_id, book_id, card_ref, dwell_ms, words, verified bool, ts)   -- partitioned by month
daily_stats(user_id, local_date, verified_cards, verified_minutes, goal_met)
streaks(user_id, current, best, last_goal_date, freezes_left, freeze_reset_at)
follows(follower_id, followee_id, created_at)
activities(id, user_id, type, payload jsonb, visibility, created_at)
kudos(activity_id, user_id) · comments(id, activity_id, user_id, body, created_at)
clubs(id, name, owner_id, privacy) · club_members(club_id, user_id, role)
challenges(id, scope, rule jsonb, starts_at, ends_at) · challenge_progress(challenge_id, user_id, value)
badges(user_id, badge_key, earned_at)
shares(id, user_id, type, payload jsonb, image_uri, created_at, open_count)
ai_usage(user_id, period_start, tier, books_used, tokens_in, tokens_out, cost_usd)
subscriptions(user_id, product_id, purchase_token, state, expires_at, region)
```
Leaderboards live in Redis sorted sets: `lb:{scope}:{scopeId}:{metric}:{period}`. They are rebuilt from `daily_stats` each night to correct drift.

---

## 8. Key Flows

### 8.1 Import → first card in under 10 seconds
1. User picks a file. The app hashes and parses it on device, and builds blocks and sentences.
2. Stage 1 rules create cards immediately, so **the user can start reading right away**.
3. In parallel: `POST /v1/books` with the hash. If a cached segment map exists for the tier, it downloads in about 1 s and replaces the rule cards from the current position onward.
4. Otherwise the current and next chapters are sent with `priority: now` (real-time API, ~5–20 s), and the remaining chapters with `priority: background` (Batch API).
5. AI cards replace rule cards for chapters ahead of the reader **without moving the reading position** (sentence-ID anchoring).

### 8.2 Reading event → streak & leaderboard
1. The app records dwell per card and sends batches every 30 s or when the app goes to the background (offline events are queued).
2. The server re-checks the dwell against word count and the user's WPM, marks events `verified`, and updates `daily_stats`.
3. When the daily goal is crossed: streak +1, push "Goal done 🔥", update leaderboards, post an activity to the feed (if visibility allows).

### 8.3 Share a card
1. Tap ⤴. The sheet opens with a preview rendered locally (no network needed).
2. Tap a target. The image is saved to cache and the Android intent fires. `POST /v1/share` runs in the background to get a short link; if offline, the link is added on a later share.

---

## 9. Non-functional Requirements
| Area | Target |
|---|---|
| Feed performance | 60 fps swipes on mid-range devices (4 GB RAM); card render < 16 ms |
| Cold start | < 2 s to the last-read card |
| Import | First readable card < 10 s for a 500-page EPUB |
| Offline | Full reading, highlights, saves, streak tracking offline; sync on reconnect |
| APK size | < 30 MB base; dictionary and on-device model are on-demand downloads |
| Availability | API 99.9%; AI pipeline failures fall back to rule cards and never block reading |
| Security | Firebase Auth tokens, server-side purchase verification, rate limits per user/IP, encryption at rest |
| Privacy | GDPR / India DPDP Act compliant; data export & account deletion in-app |
| Accessibility | WCAG 2.1 AA contrast, TalkBack support, scalable text up to 200% |

---

## 10. Metrics
- **North star:** books finished per monthly active user. Guardrails: recall accuracy, the "Did BookReel make your week better?" score, and regret rate (see UX_DESIGN.md §11). An experiment that raises time spent but lowers these counts as a failure.
- Activation: % new users reading ≥ 20 cards on day 1.
- Retention: D1 / D7 / D30; % users with a ≥ 7-day streak.
- Book completion rate (BookReel vs. industry baseline).
- Shares per WAU; installs from share links (viral coefficient).
- Segmentation quality: "cut feels wrong" reports per 1k cards; back-swipe rate.
- Free → paid conversion; churn by tier; AI cost per paying user vs. plan.

---

## 11. Roadmap
| Phase | Duration | Scope |
|---|---|---|
| **0 — Prototype** | 3 weeks | EPUB parse, rule segmenter, reel feed, Haiku segmentation on 5 books, gold-set labelling begins |
| **1 — MVP (closed beta)** | 8 weeks | EPUB + text PDF, reel + page mode, themes, TTS, dictionary, highlights, saves, sharing cards, streaks & goals, Plus tier (Haiku), sign-in & sync |
| **2 — Social & tiers** | 6 weeks | Friends, feed, kudos, leaderboards, clubs, challenges, badges, progress sharing, Pro (Sonnet) & Scholar (Opus), Batch pipeline, content-hash cache |
| **3 — Free AI & growth** | 6 weeks | On-device open-weight model for Free tier, word-list SRS, Year in Review, referral rewards, regional pricing |
| **4 — Expansion** | ongoing | iOS, more languages, audiobook sync, school/team plans |

---

## 12. Risks & Mitigations
| Risk | Mitigation |
|---|---|
| Bad cuts make cards confusing | Cuts must pass hard rules in code; gold-set evaluation gate; "Previously…" strip; user feedback loop |
| AI costs exceed revenue | ID-only output, just-in-time + Batch, content-hash cache, per-tier quotas, regional quotas, live cost dashboard with alerts |
| Copyright complaints over shared content | Short-quote limit with attribution, no sharing of book text between users, DRM-free user-owned files only, takedown process |
| Gamification encourages skimming | Dwell-verified reading, consistency-based segments, daily cap on leaderboard minutes |
| On-device model too heavy for low-end phones | Optional download, device capability check, rules-only fallback |
| PDF extraction quality (columns, footnotes) | Layout heuristics, per-book "report bad formatting", PDF marked beta in v1 |
| Model refusals on mature fiction | Server-side fallbacks (Sonnet/Opus), Haiku → Sonnet retry, rules fallback; never blocks reading |
| Play policy (subscriptions, kids) | Follow Play Billing rules; teen-safe social defaults; age gate for public leaderboards |

---

## 13. Open Questions
1. Should Free-tier users get a small monthly allowance of Haiku books (e.g. 2/month at ~$0.01 each) to show the paid quality and increase conversion?
2. Public per-card comments ("margins") on public-domain books: worth the moderation cost in v1?
3. Should the default card length depend on genre (shorter for fiction, longer for textbooks)?
4. Which regions after India and the US get regional pricing at launch?
