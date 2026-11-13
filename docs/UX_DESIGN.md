# BookReel — UX & UI Design Guidelines

| | |
|---|---|
| **Companion to** | [`DESIGN.md`](./DESIGN.md) |
| **Status** | Draft v1.0 (Revision 12) |
| **Date** | 2026-11-12 |
| **Lenses** | Behavioural psychology · Interaction & visual design · Flutter engineering |

---

> **Revision 2 (after first device tests).** Testing on a phone showed the "printed page" reader felt like a book and lost attention quickly. The reader now follows a **social-reel** style (§5.2 is superseded by this note):
> - **Snack cards** by default: 1–3 sentences (12–55 words), larger sans text revealed line by line.
> - Each card is a **post**: book avatar + title + chapter header, the author's words, and an always-visible action row (Like · Save · Note · Share · Listen) directly under the text.
> - **Gestures**: double-tap = like (heart burst), tap a sentence = highlight, swipe left = save, swipe right = share, long-press a word = meaning; a one-time guide teaches them.
> - **Calm study vibes**: hand-drawn animated scenes (forest, café, rain, ocean, night, paper) behind a tinted glass card, with gentle parallax while scrolling. Static under "Remove animations"; can be turned off.
> The ethical guardrails in §8 still apply: finite sessions, the session-complete ending, no like counts or public comparisons on cards, calm notifications.

> **Revision 3 (full-screen lyric cards + AI direction).** Cards now fill the whole screen with **lyric-style typography**: the text is split into lines at the AI's emphasised phrases and at clause breaks, the most important phrase is shown very large in the accent colour, supporting phrases in large serif italic, and lines animate in one after another. Text size is fitted to the screen (short cards get big text). Actions sit in a Reels-style right rail with the book shown bottom-left. On paid tiers the AI also picks the **scene** per chapter (Auto, crossfading when the setting changes) and plans the **soundtrack** like a film score.

> **Revision 4 (calm reels: colour, type and space).** Device feedback on Revision 3: text colours sometimes clashed with the scene, large and small type on one card did not sit well together, and text filled the screen. What changed, and why:
>
> | Change | What the reader sees | Basis |
> |---|---|---|
> | **Colours come from the scene** | Each scene has its own palette: a tinted off-white for text (parchment on the forest, latte on the café, moonlight on the night sky), one warmer or brighter tone for emphasis, and a shade over the scene in the scene's own darkest hue. The bright meadow gets dark ink on a light veil instead. No pure white, no grey overlay. | Pure white on dark "vibrates" and blooms (halation), worse for the roughly 30% of people with astigmatism; Material's dark-theme text is white at 87%, not 100%. A scrim that is darker where text sits is the standard fix for text over images. [1][2][3][4] |
> | **Measured contrast** | Body text has at least **7:1** contrast (WCAG AAA) wherever it sits; every colour and control has at least **4.5:1** (AA) everywhere. | WCAG 1.4.3 / 1.4.6. The numbers are checked on the *rendered* scenes at their brightest spots (`app/test/ui/scene_palette_test.dart`), not estimated. [5][6] |
> | **One size per reel** | Every line on a reel has the same size. The one line worth making big gets a **spotlight reel of its own**, in the book's display font. Emphasis inside a reel is colour and weight only, and never more than 40% of the reel. | Mixed sizes on one screen compete for attention; separating them keeps both readable. Spotlights are rare (at least 4 reels apart with AI direction, 7 without) so they stay special. |
> | **Room to breathe** | Text sits in the middle of the screen at the reader's own size, never enlarged to fill. Text that would not sit comfortably (long sentences are common in classics) **continues on the next reel**, split where a clause or sentence ends. | Line length and white space matter more for comfortable reading than raw size. The split follows the screen, the font size and the chosen card length. |
> | **Fonts fit the book** | Each book gets a body and a display face that suit what it is: seven voices (classic, romance, fantasy, sci-fi, suspense, modern, playful). The AI chooses on paid tiers; on-device rules use genre tags, the title and the opening pages. One font for everything (for example Atkinson Hyperlegible for low vision) is still a setting. | Genre conventions in book typography: readable serifs for fiction, clean sans for non-fiction and sci-fi, with the genre signal carried by the display face. Body faces were chosen for reading first. [7] |
>
> Sources: [1] [UX Design Institute, designing for dark mode](https://www.uxdesigninstitute.com/blog/dark-mode/) · [2] [Material Design, text legibility](https://m2.material.io/design/color/text-legibility.html) and the [dark theme codelab](https://codelabs.developers.google.com/codelabs/design-material-darktheme) · [3] [Nielsen Norman Group, text over images](https://www.nngroup.com/articles/text-over-images/) · [4] [Smashing Magazine, accessible text over images](https://smashingmagazine.com/2023/08/designing-accessible-text-over-images-part1) · [5] [W3C, Understanding Contrast (Enhanced)](https://w3c.github.io/wcag/understanding/contrast-enhanced) · [6] [MDN, colour contrast](https://developer.mozilla.org/en-US/docs/Web/Accessibility/Understanding_WCAG/Perceivable/Color_contrast) · [7] [Lulu, which font for my book](https://blog.lulu.com/which-font-should-i-use-for-my-book/) and [Kindlepreneur, typography by genre](https://kindlepreneur.com/book-cover-typography-font/). The dark-mode and genre sources are design guidance rather than controlled studies; the contrast targets are the WCAG standard.
>
> Revision 3's "text fitted to the screen" and "very large phrase on the same card" are superseded. Everything else stands: full-screen reels, the right-hand action rail, gestures, AI scenes and soundtrack.

> **Revision 5 (scene sounds instead of AI music).** The AI soundtrack is gone: licensing music for use inside an app is costly and uncertain. Instead **each scene has its own ambient sound** (rain on the window for Rain, café murmur for Café, waves for Ocean, a crackling fire for Snow, soft brown noise for Paper). It is on for every tier, follows the scene (including Auto scenes) with a crossfade, never pauses the reader's own music app, and one tap on the speaker mutes it for readers who prefer their own music. Steady natural sound also doesn't compete with the words the way speech or music with lyrics can (the "irrelevant speech effect"), so it suits reading better than songs. §6.5 is superseded.

> **Revision 6 (one immersive place, compact settings, smooth reels).** Device feedback: stock Android popups and lists broke the mood, the settings page showed every option at once, the streak and goal pills on reels did nothing, and the app felt a little slow. What changed:
>
> | Change | What the reader sees |
> |---|---|
> | **Our own UI, in the scene's colours** | Every sheet, dialog, menu, option list, toast, switch, slider, chip, time picker and the tab bar is drawn by the app (`app/lib/ui/kit.dart`), tinted with the current scene's palette (deep pine glass on Forest, espresso on Café, a warm veil on Meadow) and laid over the scene itself. No Material ripples, popup menus, snack bars or system dialogs remain. |
> | **One scene everywhere** | The reader's scene sits behind Today, Library, Notebook, Friends and Settings under an even veil, and pages cross-fade, so moving around feels like staying in one place. It moves on Today and in the reader; lists sit on a still frame of it. A floating glass dock replaces the tab bar. |
> | **Toasts that stay out of the way** | Confirmations ("Saved to your Notebook") drop in just below the top bar, leave on their own and let touches through, unless they offer an action ("Add note"). |
> | **Sheets you can flick away** | Sheets rise from the bottom; drag the handle down, tap outside or press Back to close. Text fields in them stay above the keyboard. |
> | **Reels-style share arrow** | The share button is the curved arrow of reels apps, on the rail, the swipe hint and every share button. |
> | **Tappable flame and flag** | The flame opens **Your streak** (this week day by day, best run, freezes left). The flag opens **Daily goal** (progress, daily or weekly, size, reminder, habit anchor). Today's ring and streak open the same sheets. |
> | **Compact settings** | One short list in five groups. Each row shows its current value ("Forest", "On · 60%", "Book's own fonts · 22") and opens a focused sheet; simple on/off options switch in place. |
> | **Smoother** | Scenes paint their still parts once into an image and draw only light motion (fireflies, rain, snow, stars) with pre-blurred sprites, about 30 times a second. Nothing is blurred per frame, the scene no longer repaints while reels scroll (Revision 2's parallax is gone), and it stops when hidden or in the background. Reel entrances move layers instead of rebuilding the card each frame; hard words are found once per reel; covers decode at the size shown; text has one small shadow. CI now builds **release** APKs, which run several times faster than debug builds. |
>
> Accessibility is unchanged or better: every control has a label and its actions for screen readers (switch state, slider up and down), targets are at least 48 dp, and the kit's colours are checked for every scene: text on sheets ≥ 7:1, secondary text and button labels ≥ 4.5:1 (`app/test/ui/kit_test.dart`).

> **Revision 7 (adjustable highlights, a real profile, a natural voice).**
>
> | Change | What the reader sees |
> |---|---|
> | **Highlights you can shape** | A tap still highlights the sentence at once, and now shows two handles (a caret with a round knob, like text selection) and a small toolbar: four colours, note, copy, remove, done. Dragging a handle snaps to whole words and can run across sentences on the reel; dragging one past the other swaps them. The reel holds still while adjusting; a tap elsewhere finishes. Tapping a highlight picks it up again; overlapping highlights merge (notes kept). |
> | **Profile, Instagram style** | Avatar (photo, emoji or initial; a ring once today's goal is done), books / streak / saved, name and pronouns, @username, bio, what you're reading, favourite genres, Edit profile and Share profile, a shelf of book circles with progress rings, and tabs for saved quotes (a grid), books and stats. No follower counts, no public likes: the ethical guardrails (§8) still hold. |
> | **A natural reading voice** | Listen uses a neural voice that sounds close to a person reading, with four voices and a speed setting. Audio is kept on the phone (instant, offline replays) and the next reel is fetched while one plays, so listening flows. The phone's best installed voice takes over offline. |

> **Revision 8 (a light or dark app; scenes are for reading; on-device AI on Free).**
>
> | Change | What the reader sees |
> |---|---|
> | **Appearance** | Today, Library, Notebook, Friends, Settings, Profile and onboarding use a plain theme: warm paper-white with an ember accent, or warm near-black with an amber one. **Settings → Appearance** offers *System default* (follows the phone), *Light* or *Dark*. |
> | **Scenes belong to reading** | The forest, café or rain appears only in the reader (and its session-end screen), so opening a book feels like stepping into it. Sheets opened while reading still wear the scene. Onboarding shows the scene you pick in a small window. |
> | **On-device AI (Free)** | Settings → On-device AI downloads a small model once (345 MB; a 2 GB one on phones with 8 GB of memory). It then adds recaps and quick checks every few minutes of reading, a teaser for the next chapter and "in this sentence" word meanings, all on the phone, free and offline. It can be paused or removed; phones that can't run it say why. |

> **Revision 9 (Cloro: black and white, no boxes).** The app is named Cloro. Every screen is built from black, white and greys: black (light) or white (dark) buttons, switches, chips, sliders and the selected tab. The logo red appears only on the logo, the streak flame, the liked heart and badges. Lists of options have no boxes and no lines between similar options, just one line between groups, as in Instagram and YouTube; row icons are plain. The reader keeps its scene, with menus in the same neutral black or white. Details: `docs/CLORO_PLAN.md` §3.

> **Revision 10 (day and night scenes; the scene follows your mood).**
> - **Scenes:** 4 by day (Meadow, Forest morning, Beach, Snow day) and 4 by night (Night, Rain, City, Café). The three new day scenes have dark text on a light veil, contrast-tested like the others. The picker shows DAY, then NIGHT.
> - **Mood:** while Cloro is learning (the first 15 answers, or two weeks), opening a book asks **"How are you feeling?"**, at most every 3 hours. There are seven moods, plus "Not now". The book opens in that mood's scene, by day or by night.
> - **Prediction:** after learning, Google's **Gemma** predicts the mood for this part of the day: on the phone when Gemma is downloaded, otherwise on the server. The reader's own habit is the fallback. A small **"😌 Calm · change"** chip shows for a few seconds; a tap corrects it, and corrections count double. A check-in comes about once a week.
> - **Privacy:** only the mood log (when, mood, minutes read) is ever used.
> - **Settings:** Settings → Mood turns this off, or stops the asking.
>
> Details: `docs/CLORO_PLAN.md` §5 and §8.

> **Revision 11 (Strava-style profile; following).**
> - **Following:** you follow readers one way, and the profile shows public **followers · following** counts. Revision 1's "no follower counts" guardrail is retired for these two numbers only; kudos counts stay private. Tap a count for the list, with Follow / Following buttons. Find people by @username; an invite code still makes two readers follow each other.
> - **Profile header:** photo, name · pronouns, the counts, bio, what you're reading and up to 3 genres.
> - **Profile body:** one flat scroll of This week (bars), Streak (with the heatmap), Stats (this year / all time), Trophies, Books and Saved quotes.
> - **Edit profile:** pronouns are a choice (he/him, she/her, they/them, or your own), and the photo has a crop step.
> - **Other readers:** their profiles use the same header, with Follow and "Follows you".
>
> Details: `docs/CLORO_PLAN.md` §11.

> **Revision 12 (Today: a Strava-style feed).**
> - **Layout:** Today keeps your goal ring, streak and the book to continue on top. Below is **Activity**: your reading sessions and milestones and those of readers you follow, newest first, loading more as you scroll. Pull to refresh.
> - **A session:** the book and author, time, cards, how far into the book, your mood, and a line you saved. Lines are only shared from public-domain books.
> - **Milestones:** finished books, streak milestones and a new best reading week.
> - **Responses:** kudos (no dislikes) and comments. Authors can remove comments on their own activity.
> - **Offline:** Today shows your own sessions from the phone.
> - **Goal lines** ("hit today's goal") stay out of the feed; the streak already shows them.
> - **League:** the league and the board of readers you follow move to their own League page, opened from Today and hidden with "Hide leaderboards".
>
> Details: `docs/CLORO_PLAN.md` §10.

## 0. The answer in one paragraph

The best UI for BookReel is **not** a copy of TikTok or Instagram Reels. Copy the *ease* of reels: one thing on screen, one swipe to move on, no decisions. Do **not** copy their *business model*: endless, variable-reward scrolling built to maximise time spent. We call the right approach a **"calm feed"**:

- A quiet, typography-first card that looks like a good printed page, not a social post.
- **Sessions that end**: a visible daily target and a satisfying finish screen, instead of an infinite feed.
- **Motivation from inside the reader** (feeling competent, choosing for themselves, connecting with friends) more than from points and badges.
- Small, research-backed **memory aids** (recall and reflection cards), so the time spent actually stays in the user's head.

The measure of success is not "minutes in app". It is **books finished, ideas remembered, and users who say the app made their life better.**

The rest of this document explains why and specifies the UI.

---

## 1. The core tension

| Short-video apps optimise for | BookReel must optimise for |
|---|---|
| Time spent, no matter the quality | Real reading and understanding |
| Endless novelty from unpredictable rewards | Continuity: a book is one long story or argument |
| Passive watching | Active attention |
| Compulsion | Habit plus a sense of meaning |

A key research finding guides everything here. A meta-analysis of 54 studies (Delgado et al., 2018, *Educational Research Review*) found that people **understand less when reading on screens than on paper** ("screen inferiority"). The gap was bigger **under time pressure** and for **informational text**. A fast, feed-style UI makes this worse by encouraging skimming (see also Maryanne Wolf, *Reader, Come Home*, 2018).

So the UI's job is to make reading **as easy to start as a reel, but as deep as a page.** Every decision below serves that.

---

## 2. Psychological foundations → design rules

| Principle (source) | What it says | What we design |
|---|---|---|
| **Self-Determination Theory** (Deci & Ryan) | Lasting motivation comes from **autonomy**, **competence** and **relatedness** | Autonomy: the user picks goals, card length and notification times; nothing is forced. Competence: visible growth in WPM, vocabulary, books finished, recall accuracy. Relatedness: friends, clubs, kudos |
| **Overjustification effect** (Deci 1971; Lepper, Greene & Nisbett 1973) | Outside rewards can **crowd out** the love of an activity | Points and badges stay secondary and rare. The main reward is the book itself and the feeling of progress. No XP number on every card |
| **Fogg Behavior Model**: B = M·A·P (BJ Fogg, *Tiny Habits*) | A behaviour happens when **motivation**, **ability** and a **prompt** come together | Ability: zero-friction start (open the app → straight to your next card). Prompt: one daily reminder linked to an existing habit. Motivation: progress and social features |
| **Implementation intentions** (Gollwitzer, 1999) | "When X happens, I will do Y" plans greatly improve follow-through | Onboarding asks: *"After I ___ (e.g. have morning tea), I'll read 10 cards."* The reminder uses those words |
| **Habit formation time** (Lally et al., 2009) | Habits took a **median of 66 days** to form (range 18–254); missing one day did not derail it | Streaks forgive missed days (freezes, weekly goals). Copy says "habits take ~2 months, one miss is fine" |
| **Goal-gradient effect** (Kivetz, Urminsky & Zheng, 2006) | People speed up as they get closer to a goal | A segmented daily-goal bar at the top of the reader that fills card by card |
| **Endowed progress effect** (Nunes & Drèze, 2006) | Goals that start partly complete are finished more often | Onboarding cards count toward day 1's goal. A new book shows "Chapter 1 started" after the first card |
| **Flow** (Csikszentmihalyi) | Deep engagement needs clear goals, instant feedback, and challenge matched to skill | Card length adapts to reading speed. Instant subtle feedback on swipes. Nothing interrupts the reading surface |
| **Peak-end rule** (Kahneman et al., 1993) | Experiences are remembered by their peak and their **end** | Every session ends on a designed "Session complete" screen with the day's best idea, not by just closing the app |
| **Fresh-start effect** (Dai, Milkman & Riis, 2014) | New beginnings (Mondays, months, birthdays) prompt goal-setting | Weekly and monthly challenges start on those dates; "new week, new book?" prompts |
| **Testing effect** (Roediger & Karpicke, 2006) & **spacing** (Ebbinghaus) | Recalling information beats rereading it for long-term memory, especially when spaced out | Optional one-tap **Recall cards** every ~10 cards. Saved cards and words return later in spaced review |
| **Generation & self-reference effects** | We remember better what we produce ourselves and what we link to our own lives | Chapter-end **Reflect card**: "One idea you'll use this week?" (optional, saved to notes) |
| **Social comparison** (Festinger, 1954) | Comparing yourself with people far ahead often **demotivates** | Default leaderboards are Friends plus small **leagues** of ~20–30 similar readers, not a global ranking. Rank by consistency, not raw volume |
| **Loss aversion** (Kahneman & Tversky) | Losses feel about twice as strong as gains, so streaks motivate but can cause anxiety | Use loss aversion gently: freezes, "repair streak", and **never shaming copy**. Option to switch to a weekly goal |
| **Cognitive load theory** (Sweller) | Working memory is small; extra visual detail takes attention away from learning | The reading surface shows only text plus a thin progress bar. All controls fade out while reading |
| **Calm Technology** (Weiser & Brown; Amber Case) | Technology should need little attention and stay in the background | Few, well-timed notifications; ambient progress; no red badges or counters on the app icon |
| **Humane design / "Time Well Spent"** (Center for Humane Technology) & **deceptive patterns** (Harry Brignull) | Don't exploit psychological weaknesses | See the anti-pattern list in §8 |

---

## 3. Design principles for BookReel

Drawn from Dieter Rams ("less, but better"), Don Norman (*The Design of Everyday Things*: signifiers, feedback, mapping), Nielsen's 10 usability heuristics, Material Design 3, and *Refactoring UI* (Wathan & Schoger).

1. **The text is the interface.** Typography does 80% of the design work. Chrome is minimal and fades away while reading.
2. **One thumb, one decision.** Every main action can be reached one-handed in the natural thumb zone. Steven Hoober's field observations found ~49% of phone use is one-handed.
3. **Finite and satisfying.** Every session has a visible target and a designed ending.
4. **Progress you can feel.** Small, honest feedback on every card; larger celebrations only for real milestones. Rarity keeps them meaningful.
5. **Depth on demand.** Meanings, highlights, notes and recall are always one gesture away and never in the way.
6. **Kind by default.** The copy, colours and notifications support the user and never shame them.
7. **The user is in control.** Every motivational mechanic (streaks, leaderboards, reminders, recall cards) can be adjusted or turned off. This is autonomy (SDT) and Nielsen's "user control and freedom".
8. **Fast is a feature.** Responses under 100 ms feel instant; under 400 ms (the Doherty threshold) keeps users in flow. Never show a spinner on the reading path.

---

## 4. Information architecture

Bottom navigation (Material 3 `NavigationBar`) with **4 destinations**, kept to the minimum (Hick's law):

| Tab | Purpose |
|---|---|
| **Today** (home) | One big "Continue reading" button, today's goal ring, streak, and one social update. Opening the app → one tap → reading |
| **Library** | Books, shelves, import, starter classics |
| **Notebook** | Saved cards, highlights, notes, word list, reflections: everything the user *kept* |
| **Friends** | Activity feed, kudos, league, clubs, challenges |

Profile and settings sit behind the avatar at the top right of **Today**. The reader opens full screen, outside the tab structure, so nothing competes with the text.

> Why "Notebook" is a tab: what the user *keeps* is the lasting value of the app. Making it a main destination tells users that reading here builds something that belongs to them (Hooked model's "investment" step, used ethically).

---

## 5. Screen specifications

### 5.1 Today (home)
```
┌─────────────────────────────────┐
│ Good morning, Asha        (👤)  │
│                                 │
│        ╭──────────╮             │
│        │  6 / 10  │  🔥 23 days │  ← goal ring (fills like Apple Activity rings)
│        ╰──────────╯             │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ [cover] Atomic Habits       │ │
│ │ Ch. 4 · 38% · ~11 min left  │ │
│ │ in chapter                  │ │
│ │      ▶  Continue reading    │ │  ← primary action, bottom half of screen
│ └─────────────────────────────┘ │
│                                 │
│ Rahul finished "Sapiens" 👏      │  ← ONE social item, not a feed
│ Your league: #4 of 24 · ↑2      │
│                                 │
│ [Today] [Library] [Notebook] [Friends]
└─────────────────────────────────┘
```
- **One main action.** Large, in the thumb zone, uses the accent colour.
- The goal ring shows *today*, not lifetime totals; a small, reachable goal.
- Time left is shown **per chapter** ("~11 min left in chapter"), not per book. A small, nearby goal motivates more (goal gradient).

### 5.2 The reader (core screen)

```
┌─────────────────────────────────┐
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬▭▭▭▭▭▭▭▭▭▭▭       │  ← segmented goal bar (Stories pattern), 2dp
│ Ch. 4 · The Habit Loop          │  ← small, 60% opacity, fades after 2 s
│                                 │
│ Why cravings beat willpower     │  ← optional AI title, small caps, muted
│                                 │
│ The author's original text set  │
│ in a reading typeface, left-    │  ← 18–20sp, line-height 1.55,
│ aligned, generous margins, with │     ~35–45 characters per line
│ the key point softly tinted and │
│ rare words dotted-underlined.   │
│                                 │
│                                 │
│   ♡      ✎       🔖      ⤴      │  ← bottom action row, low contrast,
└─────────────────────────────────┘     brightens on touch
```

**Key decisions and why**
| Decision | Reason |
|---|---|
| **Bottom action row, not a TikTok-style right rail** | A right rail takes ~15% of the width of every line of text and puts icons next to the words. Text gets the full width; actions stay in the thumb zone |
| **Chrome fades after ~2 s of no touch**; tap the text margin to bring it back | Reduces cognitive load; same as Kindle and Apple Books. Reading is the focus |
| **Segmented goal bar at the top** | Instagram Stories pattern people already know; shows "how far to today's goal" (goal gradient); finite, not infinite |
| **Left-aligned, ragged-right text** (justification optional) | Justified text on narrow phone columns creates uneven gaps ("rivers") that slow reading (Bringhurst; Butterick's *Practical Typography*) |
| **Text vertically centred** when shorter than the screen; **top-aligned** when long | Short cards feel like intentional "quote" moments; long cards read naturally from the top |
| **Long cards scroll inside the card**; swipe to the next card only from the end of the card | A swipe never skips text the user hasn't seen. A soft "elastic" edge shows that more text is below |
| **Swipe physics:** snap with a slight resistance (critically damped spring) | Gives a "page turn" feeling. Too slippery encourages flicking past cards |
| **Light haptic tick on every card change**, success haptic when the goal is met | Feedback without visual clutter (Norman: feedback) |
| **No like counts, view counts or comments on cards** | Social numbers on content turn reading into scanning for popularity and add noise |

**Special cards (from DESIGN.md §2.2), styled to stand out from book text:**
- **Chapter card:** full-bleed, large serif chapter title, "12 cards · ~8 min". A breathing point.
- **Recall card** (new, optional, every ~10 cards): *"Quick check: what was the main idea?"* with 3 AI-written options, or "Tap to reveal". Feedback in one tap; no penalty for wrong answers. Can be turned off. Uses the testing effect.
- **Recap card:** 2–3 bullets, marked with an "AI summary" chip so it is never confused with the author's text.
- **Reflect card** (chapter end, optional): *"One idea you'll try this week?"* Typing saves to Notebook; "Skip" is equally prominent.
- **"Previously…" strip:** a slim banner shown above the text after breaks of more than 24 h.

### 5.3 Session complete (designed ending: peak-end rule)
Shown when the daily goal is reached and at the end of a chapter:
```
┌─────────────────────────────────┐
│            ✓ Goal done          │
│        10 cards · 9 min         │
│          🔥 24-day streak        │
│                                 │
│  Your idea of the day:          │
│  "You do not rise to the level  │  ← the user's highlight, or the AI key point
│   of your goals…"               │
│                                 │
│  [ Share ]      [ Keep reading ]│
│           Done for today        │  ← text button, clearly visible
└─────────────────────────────────┘
```
- Celebrates the user and gives a **natural stopping point**. "Keep reading" is offered as a choice, not pushed. Users who choose to continue read with intention; users who stop leave feeling good, and that good feeling is what brings them back tomorrow.
- One-tap share of the idea or the progress (DESIGN.md §2.6).

### 5.4 Word sheet
- Long-press a word → a bottom sheet at half height (Material 3 modal bottom sheet). The text above stays visible so context is kept.
- Order: **meaning in this sentence** (largest) → dictionary definition → pronunciation ▶ → translation → **"+ Word list"**.
- Closes with a swipe down; the reading position doesn't move.

### 5.5 Highlight & note
- Double-tap a sentence → highlighted in the default colour with a short spread animation (~200 ms). Double-tap again → a small colour picker plus "Add note".
- Long-press and drag → precise selection with Material handles.
- Highlights use **tints, not saturated colours** (≤ 25% opacity backgrounds) so text contrast stays above WCAG AA.

### 5.6 Share sheet
- The preview appears **immediately** (rendered locally); there is no "Generate" step.
- The share targets the user picked last time appear first.
- Templates are a horizontal carousel, at most 5. Too many choices slow people down (Hick's law; the choice-overload research of Iyengar & Lepper, 2000).

### 5.7 Friends
- **League view** (default): ~24 readers of similar level, weekly, top 5 move up. Ranked by **verified active days and minutes**, with daily caps.
- **Activity feed:** read-only cards with **Kudos** (👏) and short comments; no dislikes, no follower counts on profiles by default.
- **Clubs:** shared current book, a club progress bar ("Club is 63% through *1984*"), and a gentle "Asha is on chapter 9, you're on 7" comparison between friends.
- Anyone can turn off comparisons entirely ("Hide leaderboards"). For some people, competition causes stress.

### 5.8 Progress / profile
- Show **growth**, not just totals: reading speed trend, vocabulary learned, books finished, recall accuracy, longest streak, and a reading calendar heat map (GitHub/Strava style).
- "Year in Review" and monthly recap cards are designed to be shared.

### 5.9 Onboarding (≤ 60 seconds to first card)
1. **Value in one screen:** "Read books in bite-sized cards. Build a habit that sticks."
2. Pick 3 interests → suggested starter book (already processed) → **reading starts immediately.** The tutorial *is* the first 3 cards, with coach marks for swipe, long-press word, and share.
3. *After* the first cards, when motivation is highest: set the daily goal (default 10 cards; offer 5/10/20) and the habit anchor: "After I ___, I'll read." Then ask for notification permission, explaining why first.
4. Sign-in is offered later (when saving or adding friends), not as a wall at the start.

### 5.10 Notifications (calm by default)
| Type | Default | Copy style |
|---|---|---|
| Daily reminder at the user's chosen time | On (1/day max) | "After your morning tea: 10 cards of *Atomic Habits*? ☕" (uses their own words) |
| Streak protection | On, **only** if no reading by 8 pm local | "Your 23-day streak is safe with a freeze, or read 3 cards to keep it going." Never threatening |
| Social (kudos, friend finished a book) | Grouped into one daily digest | Positive only |
| League/challenge results | Weekly | Celebrate progress; don't dwell on losses |
| Win-back after 7+ days away | Once, then quiet | "Welcome back anytime, you were on chapter 4." **No guilt** |

No red badge counts on the app icon. Quiet hours by default from 22:00 to 08:00.

---

## 6. Visual design system

### 6.1 Typography (the most important part of the visual design)
| Use | Typeface | Why |
|---|---|---|
| Reading text (default) | **Literata** (serif) | Designed by TypeTogether for Google Play Books, for long reading on screens; open-licensed |
| Reading text (alternative) | **Atkinson Hyperlegible**, Source Serif, Merriweather, system sans | Choice supports autonomy; Atkinson (Braille Institute) is designed for low-vision legibility |
| UI | **Inter** or Roboto Flex | Neutral, legible at small sizes, works with Material 3 type scales |

- Body size **18sp** by default (range 14–32sp; follows the system font scale up to 200%).
- **Line height 1.5–1.6**, paragraph spacing 0.8 em, side margins 24dp.
- **Line length about 35–45 characters** on phones. Bringhurst's ideal of 45–75 characters (66 best) is for print columns; phones are narrower, so don't shrink type to fit more on a line.
- **On dyslexia:** studies of special "dyslexia fonts" (e.g. Wery & Diliberto, 2017 on OpenDyslexic) found **no reading benefit**. Wider **letter spacing** did help (Zorzi et al., 2012, *PNAS*). So we offer a "spacing" slider (letter and word spacing) in addition to fonts.

### 6.2 Colour
- **The reading surface uses fixed, carefully chosen themes**: Paper (#FBF8F1 bg / #1F1D1A text), White, Sepia, Dark (#141414 bg / #E6E1D6 text, slightly warm, not pure white, to reduce halation), and AMOLED Black as an option. All body text ≥ 7:1 contrast (WCAG AAA).
- **App chrome uses Material 3 dynamic colour** (Material You) to feel at home on Android, but the reading surface never takes on wallpaper colours.
- **One accent colour** (e.g. a warm amber "ember") for primary actions, the streak flame and goal progress. *Refactoring UI*: use colour for meaning, not decoration.
- **No red for losses.** A broken streak shows in neutral grey with a "start again" message; red signals danger and causes stress.
- Highlights: 4 tints (amber, green, blue, pink) at ≤ 25% opacity, also distinguishable by colour-blind users (tested with deuteranopia and protanopia simulators).

### 6.3 Spacing, layout, touch
- 4dp base grid; 8/16/24/32 spacing scale.
- **Touch targets ≥ 48×48dp** (Material), even when the icon is 24dp.
- Main actions in the bottom 40% of the screen; destructive actions never in the easy thumb zone.
- A left-handed mode mirrors the action row.

### 6.4 Motion & haptics
- Material 3 motion: standard easing; **150–300 ms** for UI changes; card swipe driven by a physics spring.
- Celebrations (confetti, flame burst) **only** for the daily goal, finishing a chapter or book, and streak milestones (7/30/100/365). Rarity keeps them meaningful.
- Follow system **"Remove animations"**: celebrations become simple fades.
- Haptics: `selectionClick` on each card, `mediumImpact` on goal completion, none for errors.

### 6.5 Sound
Each scene's own ambient sound, on by default, with its own volume control and a one-tap mute in the reader (see Revision 5).

### 6.6 Voice & tone
- Warm, short, encouraging. Talk about the user, not the app ("You read 3 books this month", not "BookReel helped you…").
- Never shame or threaten ("You'll lose your streak!" → "Keep your 23-day streak going?").
- Plain language at about a grade-8 reading level for all UI copy.

---

## 7. Gamification done right

| Mechanic | ✅ Do | ❌ Don't |
|---|---|---|
| **Streak** | Freezes, repair within 48 h, weekly-goal mode ("5 of 7 days"), celebrate milestones | Punish, guilt-trip, sell streak repairs aggressively |
| **Daily goal** | Small default (10 cards ≈ 5–8 min), user-chosen, adapts if often missed ("Try 5 cards for now?") | Raise goals automatically to increase engagement |
| **Leaderboards** | Small leagues of similar readers, friends, consistency-based, opt-out | A global top-100 by default; ranking by raw cards (encourages skimming) |
| **Badges / XP** | Few, tied to meaningful milestones (first book, 30-day habit, 100 words learned) | A badge for everything; XP numbers flashing on every card |
| **Variable reward** | Comes from the content itself (the next idea in the book) and occasional pleasant surprises ("You've highlighted 50 ideas, see your best ones") | Random loot, spin wheels, artificial cliffhangers |
| **Social** | Kudos, encouragement, shared club goals | Public shaming ("Rahul passed you!") pushes, follower counts, like counts on cards |

---

## 8. Ethical guardrails: patterns we will never ship
Based on Harry Brignull's deceptive-pattern taxonomy and humane-technology principles:
1. **No infinite cross-book autoplay feed** as the default. Feeds are per book and per session, with natural stopping points.
2. **No confirmshaming** ("No thanks, I don't like reading").
3. **No fake urgency or scarcity** in subscription upsells; prices and renewal dates are clearly shown; cancelling is easy and in-app.
4. **No dark nudges at night**: no reminders during quiet hours; a "Wind-down" theme encourages stopping at bedtime.
5. **No hidden auto-advance.** Auto-advance is opt-in and always visibly marked.
6. **No paid ways to beat friends** (no buying XP or leaderboard boosts).
7. **Paywalls never interrupt a card or a session.** Upsells appear only on the Today screen or settings, at most once per week.

---

## 9. Accessibility (WCAG 2.2 AA minimum)
- Text contrast ≥ 4.5:1 for UI, ≥ 7:1 on the reading surface.
- Full TalkBack support: each card reads as one paragraph with semantic headings; custom actions ("Save", "Share", "Define word") in the TalkBack menu; swipe-card navigation also works with TalkBack's scroll actions.
- Dynamic type up to 200% without truncation; the layout re-flows.
- Touch targets ≥ 48dp; no gesture-only features (every gesture has a button alternative, e.g. "Next" in the ⋯ menu).
- Respect "Remove animations" and the system dark theme.
- TTS read-along with sentence highlighting helps low-vision and dyslexic readers.

---

## 10. Engineering notes (Flutter)
| Concern | Approach |
|---|---|
| Design tokens | `ThemeData` (Material 3, `useMaterial3: true`) + a `ThemeExtension<ReadingTheme>` for reading-surface colours, type and spacing, so themes and fonts change in one place |
| Dynamic colour | `dynamic_color` package for chrome only |
| Reader feed | Vertical `PageView.builder` with custom `ScrollPhysics` (spring with resistance) and ±2 pages built ahead. Long cards use an inner `SingleChildScrollView` with `NotificationListener` to hand off to the pager at the edge |
| Text rendering | `Text.rich` with one `TextSpan` per sentence (for highlight, tap and TTS targets). Cache `TextPainter` layouts per (card, font settings). Impeller renderer (default on Android in recent Flutter) |
| Chrome fade | `AnimatedOpacity` driven by an inactivity timer; `IgnorePointer` while hidden |
| Haptics | `HapticFeedback.selectionClick()` / `mediumImpact()` |
| Reduced motion | Check `MediaQuery.disableAnimationsOf(context)` before playing celebrations |
| Text scaling | Respect `MediaQuery.textScalerOf(context)`; test at 1.0, 1.5, 2.0 |
| Performance budget | No frame over 16 ms on a 4 GB RAM test device; check with the DevTools performance overlay in CI integration tests |
| Share images | Off-screen `RepaintBoundary` → `toImage(pixelRatio:)` at 1080×1920; render in a microtask after the sheet opens so opening it is instant |
| Golden tests | Golden (screenshot) tests for every card type × 5 themes × 3 text scales |

---

## 11. Measuring "value added", not just engagement

| Category | Metric | Why |
|---|---|---|
| Habit | % WAU with ≥ 4 active days/week; median streak | A sign the habit is forming |
| Depth | **Books finished per user per month**; % cards verified (not skimmed) | Real reading, not scrolling |
| Learning | Recall-card accuracy; 7-day recall on spaced review; words kept in the word list | Did the reading stick? |
| Wellbeing | Monthly 1-question in-app survey: *"Did BookReel make your week better?"* (1–5); **regret rate**: "Do you wish you'd spent that time differently?" | Checks against building a compulsion |
| Health guardrails | Late-night usage share; sessions over 2 h; notification opt-out rate | Warning signs of compulsive use or annoyance |
| Growth | Shares per WAU; installs per share | Viral loop |

**Rule:** an A/B test that raises time spent but lowers books finished, recall accuracy, or the wellbeing score is a **failed test.**

### Validation plan
1. **Paper/Figma prototypes** → 5-user usability tests per round (Nielsen: 5 users find most usability problems), 3 rounds before beta.
2. **Comprehension study** in closed beta: same chapters read in Reel mode (with and without recall cards) vs Page mode; measure understanding. If Reel mode is worse, tune card length and recall frequency until it matches or beats Page mode.
3. **Diary study** (2 weeks, 10–15 users) on habit formation and feelings about streaks and leagues.
4. Ongoing A/B tests with the guardrail metrics above.

---

## 12. Changes made to `DESIGN.md` because of this document
- The cross-book "Continue reading" infinite feed became a **session-based** experience with a designed ending (§5.3).
- Card actions moved from a right rail to a **bottom action row** (§5.2).
- Added **Recall** and **Reflect** cards (§5.2).
- The default leaderboard scope is **Friends + Leagues**; Global is opt-in (§5.7).
- The streak-risk notification moved to 8 pm and uses non-threatening copy; social notifications are grouped into a daily digest (§5.10).
- Added a **weekly-goal** alternative to daily streaks (§7).
- The dyslexia-font option is joined by a **letter/word spacing** control (§6.1).
