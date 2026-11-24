/* Cloro — cloro.in. Small, dependency-free interactions. Every module runs
   only where its markup is, and the page works without any of it. */
(() => {
  "use strict";

  const doc = document;
  const root = doc.documentElement;
  const $ = (s, el = doc) => el.querySelector(s);
  const $$ = (s, el = doc) => [...el.querySelectorAll(s)];
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  root.classList.add("js");

  // ------------------------------------------------------------ icons

  const icon = (d, { fill = false, w = 2 } = {}) =>
    `<svg viewBox="0 0 24 24" aria-hidden="true" fill="${fill ? "currentColor" : "none"}" stroke="${fill ? "none" : "currentColor"}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
  const ICONS = {
    heart: icon('<path d="M12 20.2s-7.6-4.6-9.4-9.4C1.4 7.4 3.6 4.4 7 4.4c2.1 0 3.8 1.2 5 3 1.2-1.8 2.9-3 5-3 3.4 0 5.6 3 4.4 6.4-1.8 4.8-9.4 9.4-9.4 9.4z"/>'),
    heartFill: icon('<path d="M12 20.2s-7.6-4.6-9.4-9.4C1.4 7.4 3.6 4.4 7 4.4c2.1 0 3.8 1.2 5 3 1.2-1.8 2.9-3 5-3 3.4 0 5.6 3 4.4 6.4-1.8 4.8-9.4 9.4-9.4 9.4z"/>', { fill: true }),
    save: icon('<path d="M7 3.8h10a1 1 0 0 1 1 1v15.4l-6-4.3-6 4.3V4.8a1 1 0 0 1 1-1z"/>'),
    note: icon('<path d="M4 6.5h11M4 11h11M4 15.5h6"/><path d="M13.5 20.2l.8-3.2 5.6-5.6a1.6 1.6 0 0 1 2.3 2.3l-5.6 5.6z"/>'),
    share: icon('<path d="M13.2 4.2 21 11.6l-7.8 7.4v-4.3c-5 0-8.4 1.5-10.2 4.9.7-5.6 3.9-9.4 10.2-10.1z"/>', { fill: true }),
    listen: icon('<path d="M4 15.5v-3a8 8 0 0 1 16 0v3"/><rect x="3" y="14" width="4.4" height="6.4" rx="1.6"/><rect x="16.6" y="14" width="4.4" height="6.4" rx="1.6"/>'),
    flame: icon('<path d="M12 22c-4.2 0-7.3-2.9-7.3-6.8 0-3.2 2-5.4 3.8-7.2.4 1.8 1.3 3 2.5 3.7.2-3.5 1.4-6.8 4.3-9.7.3 3.5 1.8 5.6 3.1 7.4 1.2 1.7 2 3.5 2 5.8C20.4 19 16.6 22 12 22z"/>', { fill: true }),
    goal: icon('<path d="M6 21V4M6 4.5h11.5l-2.3 4 2.3 4H6"/>'),
    met: icon('<circle cx="12" cy="12" r="9"/><path d="M8 12.4l2.8 2.8L16.2 9.8"/>', { w: 2.2 }),
    more: icon('<circle cx="5" cy="12" r="1.9"/><circle cx="12" cy="12" r="1.9"/><circle cx="19" cy="12" r="1.9"/>', { fill: true }),
    up: icon('<path d="M5 15l7-7 7 7"/>', { w: 2.4 }),
    down: icon('<path d="M5 9l7 7 7-7"/>', { w: 2.4 }),
  };
  const STATUS = `<div class="status" aria-hidden="true"><span>9:41</span><span class="status__icons">
    <svg viewBox="0 0 18 12" fill="currentColor"><rect x="0" y="8" width="3" height="4" rx=".8"/><rect x="5" y="5.5" width="3" height="6.5" rx=".8"/><rect x="10" y="3" width="3" height="9" rx=".8"/><rect x="15" y="0" width="3" height="12" rx=".8"/></svg>
    <svg viewBox="0 0 16 12" fill="currentColor"><path d="M8 11.6 0 3.5A11.4 11.4 0 0 1 16 3.5z"/></svg>
    <svg viewBox="0 0 26 12"><rect x=".7" y=".7" width="22" height="10.6" rx="3" fill="none" stroke="currentColor" stroke-opacity=".45" stroke-width="1.2"/><rect x="2.4" y="2.4" width="15.2" height="7.2" rx="1.6" fill="currentColor"/><rect x="24" y="4" width="1.6" height="4" rx=".8" fill="currentColor" fill-opacity=".45"/></svg>
  </span></div>`;

  // The status bar on every phone (decoration, drawn here to keep pages lean).
  $$(".phone__screen").forEach((s) => {
    if (!$(".status", s)) s.insertAdjacentHTML("beforeend", STATUS);
  });
  $$("[data-icon]").forEach((el) => {
    const name = el.getAttribute("data-icon");
    if (ICONS[name]) el.insertAdjacentHTML("afterbegin", ICONS[name]);
  });

  // ---------------------------------------------------------------- nav

  const nav = $(".nav");
  if (nav) {
    const onScroll = () => nav.classList.toggle("is-scrolled", scrollY > 8);
    addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    const toggle = $(".nav__toggle");
    const menu = $(".menu");
    if (toggle && menu) {
      const set = (open) => {
        root.classList.toggle("menu-open", open);
        toggle.setAttribute("aria-expanded", String(open));
        toggle.setAttribute("aria-label", open ? "Close menu" : "Menu");
        menu.toggleAttribute("inert", !open);
        if (open) $("a", menu)?.focus({ preventScroll: true });
      };
      menu.toggleAttribute("inert", true);
      toggle.addEventListener("click", () => set(!root.classList.contains("menu-open")));
      menu.addEventListener("click", (e) => {
        if (e.target.closest("a")) set(false);
      });
      addEventListener("keydown", (e) => {
        if (e.key === "Escape" && root.classList.contains("menu-open")) {
          set(false);
          toggle.focus();
        }
      });
      matchMedia("(min-width: 821px)").addEventListener("change", (e) => e.matches && set(false));
    }
  }

  // ------------------------------------------------------------- reveal

  const revealed = $$("[data-reveal]");
  if (revealed.length) {
    if (!("IntersectionObserver" in window)) {
      revealed.forEach((el) => el.classList.add("is-in"));
    } else {
      const io = new IntersectionObserver(
        (entries) =>
          entries.forEach((e) => {
            if (!e.isIntersecting) return;
            e.target.classList.add("is-in");
            io.unobserve(e.target);
          }),
        { rootMargin: "0px 0px -8% 0px", threshold: 0.12 },
      );
      revealed.forEach((el) => io.observe(el));
    }
  }

  // A frame-throttled scroll loop for the scroll-linked effects below.
  const onFrame = [];
  let ticking = false;
  const tick = () => {
    ticking = false;
    onFrame.forEach((f) => f());
  };
  const schedule = () => {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(tick);
    }
  };
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", schedule, { passive: true });

  // ---------------------------------------------- hero: phone rises, chips drift

  const stage = $(".hero__stage");
  if (stage) {
    onFrame.push(() => {
      if (reduced.matches) return stage.style.setProperty("--p", "0");
      const r = stage.getBoundingClientRect();
      const p = clamp(1 - (r.top + r.height * 0.35) / innerHeight, 0, 1);
      stage.style.setProperty("--p", p.toFixed(3));
    });
  }

  // ---------------------------------------- manifesto: words light up as you read

  $$(".manifesto").forEach((el) => {
    const walk = (node) => {
      [...node.childNodes].forEach((n) => {
        if (n.nodeType === 3) {
          const frag = doc.createDocumentFragment();
          n.textContent.split(/(\s+)/).forEach((part) => {
            if (!part) return;
            if (/^\s+$/.test(part)) return frag.append(part);
            const w = doc.createElement("span");
            w.className = "w" + (node.classList?.contains("brand") ? " brand" : "");
            w.textContent = part;
            frag.append(w);
          });
          n.replaceWith(frag);
        } else if (n.nodeType === 1) walk(n);
      });
    };
    walk(el);
    const words = $$(".w", el);
    onFrame.push(() => {
      const r = el.getBoundingClientRect();
      const start = innerHeight * 0.88;
      const end = innerHeight * 0.32;
      const p = reduced.matches ? 1 : clamp((start - r.top) / (start - end + r.height * 0.6), 0, 1);
      const lit = Math.round(p * words.length);
      words.forEach((w, i) => w.classList.toggle("is-lit", i < lit));
    });
  });

  // ------------------------------------- story: the phone follows the steps

  $$("[data-story]").forEach((story) => {
    const steps = $$(".story__step", story);
    const screens = $$(".screens > [data-screen]", story);
    const pill = $(".listen-pill", story);
    const show = (i) => {
      steps.forEach((s, k) => s.classList.toggle("is-active", k === i));
      const name = steps[i]?.dataset.show;
      screens.forEach((s) => s.classList.toggle("is-active", s.dataset.screen === name));
      pill?.classList.toggle("is-on", steps[i]?.dataset.pill === "on");
    };
    show(0);
    const io = new IntersectionObserver(
      (entries) => entries.forEach((e) => e.isIntersecting && show(steps.indexOf(e.target))),
      { rootMargin: "-48% 0px -48% 0px" },
    );
    steps.forEach((s) => io.observe(s));
  });

  // ----------------------------------------------------------- the reel

  const SCENES = {
    studyNight: { ink: "#F6F2EA", emph: "#FFD49A", tint: "15 15 21", shade: [0.18, 0.18, 0.18, 0.18, 0.38, 0.4, 0.6, 0.6, 0.6, 0.42, 0.18], light: false },
    studyCafe: { ink: "#F6F2EA", emph: "#F7C089", tint: "22 15 14", shade: [0.21, 0.21, 0.43, 0.53, 0.53, 0.53, 0.56, 0.56, 0.56, 0.53, 0.18], light: false },
    studySun: { ink: "#1C1A17", emph: "#6B3A0B", tint: "245 245 240", shade: [0.42, 0.42, 0.42, 0.42, 0.44, 0.44, 0.49, 0.5, 0.5, 0.5, 0.31], light: true },
    rain: { ink: "#E8EFF7", emph: "#AFD3F8", tint: "6 13 25", shade: [0.14, 0.14, 0.14, 0.16, 0.28, 0.28, 0.16, 0.14, 0.14, 0.24, 0.3], light: false },
    meadow: { ink: "#24301F", emph: "#6B3F0C", tint: "255 250 236", shade: [0.08, 0.08, 0.08, 0.08, 0.09, 0.21, 0.33, 0.45, 0.45, 0.38, 0.37], light: true },
    night: { ink: "#ECEBF8", emph: "#D3C7FF", tint: "4 7 26", shade: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24, 0.3], light: false },
  };
  // The app's own dictionary (WordNet 3.0), for the words underlined in the demo.
  const MEANINGS = {
    peep: [["verb", "look furtively", "He peeped at the woman through the window"], ["noun", "a secret look"]],
    conversation: [["noun", "the use of speech for informal exchange of views or ideas or information etc."]],
    consider: [["verb", "give careful consideration to", "consider the possibility of moving"], ["verb", "deem to be"]],
    daisy: [["noun", "any of numerous composite plants having flower heads with well-developed ray flowers usually arranged in a single whorl"]],
    remarkable: [["adjective", "unusual or striking", "a remarkable sight"], ["adjective", "worthy of notice"]],
    waistcoat: [["noun", "a man's sleeveless garment worn underneath a coat"]],
    curiosity: [["noun", "a state in which you want to learn more about something"], ["noun", "something unusual -- perhaps worthy of collecting"]],
    hedge: [["noun", "a fence formed by a row of closely planted shrubs or bushes"]],
  };

  const paintScene = (reel, name) => {
    const s = SCENES[name] || SCENES.studyNight;
    const stops = s.shade.map((a, i) => `rgb(${s.tint} / ${a}) ${(i * 10).toFixed(0)}%`).join(", ");
    reel.style.setProperty("--ink", s.ink);
    reel.style.setProperty("--emph", s.emph);
    reel.style.setProperty("--tint", s.tint);
    reel.style.setProperty("--shade", `linear-gradient(to bottom, ${stops})`);
    reel.style.setProperty("--shadow", s.light ? `0 0 6px rgb(${s.tint} / .85)` : `0 1px 5px rgb(${s.tint} / .75)`);
    reel.classList.toggle("reel--light", s.light);
    const phone = reel.closest(".phone__screen")?.parentElement;
    if (phone) phone.dataset.status = s.light ? "dark" : "light";
  };

  // A video that plays only while it's on screen; never with reduced motion,
  // Data Saver or a 2G connection (the still poster stays instead).
  const conn = navigator.connection;
  const lightData = !!(conn && (conn.saveData || /2g/.test(conn.effectiveType || "")));
  const playInView = (video) => {
    if (!video || lightData) return;
    const io = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting && !reduced.matches) {
          if (video.preload === "none") video.preload = "auto";
          video.play().catch(() => {});
        } else video.pause();
      },
      { threshold: 0.15 },
    );
    io.observe(video);
  };

  // Hero: the reels turn on their own, like the app read hands-free.
  $$("[data-reel='auto']").forEach((reel) => {
    paintScene(reel, reel.dataset.scene);
    playInView($("video", reel));
    const feed = $(".reel__feed", reel);
    const pages = $$(".reel__page", feed);
    const goal = $(".reel__goal", reel);
    let i = 0;
    let timer = 0;
    let visible = false;
    const go = () => {
      i = (i + 1) % pages.length;
      feed.scrollTo({ top: i * feed.clientHeight, behavior: i === 0 ? "auto" : "smooth" });
      goal?.style.setProperty("--goal", String(i / (pages.length - 1)));
      goal?.classList.toggle("is-met", i === pages.length - 1);
    };
    const run = () => {
      clearInterval(timer);
      if (visible && !reduced.matches && !doc.hidden) timer = setInterval(go, 4200);
    };
    new IntersectionObserver(([e]) => {
      visible = e.isIntersecting;
      run();
    }).observe(reel);
    doc.addEventListener("visibilitychange", run);
  });

  // The demo: swipe, like, save, meanings, listen, scenes, and a goal that
  // counts only real reading, as in the app.
  $$("[data-reel='demo']").forEach((reel) => {
    const feed = $(".reel__feed", reel);
    const pages = $$(".reel__page", feed);
    const goalBar = $(".reel__goal", reel);
    const sheet = $(".sheet", reel);
    const toastEl = $(".toast", reel);
    const rail = $(".rail", reel);
    const goalTarget = Number(reel.dataset.goal || 5);
    const dwellMs = Number(reel.dataset.dwell || 2500);
    const counted = new Set();
    let current = 0;
    let shownAt = performance.now();
    let warnedQuick = false;
    let goalMet = false;
    let toastTimer = 0;
    paintScene(reel, reel.dataset.scene);
    const bgVideo = $(".reel__bg video", reel);
    playInView(bgVideo);

    const toast = (text) => {
      if (!toastEl) return;
      toastEl.textContent = text;
      toastEl.classList.add("is-on");
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => toastEl.classList.remove("is-on"), 1900);
    };
    const isText = (p) => p?.classList.contains("reel__text-page");

    // Each word in its own span (for read-aloud highlighting); offsets into
    // the plain text the voice reads.
    pages.filter(isText).forEach((page) => {
      let offset = 0;
      const text = $(".reel__text", page);
      const walk = (node) => {
        [...node.childNodes].forEach((n) => {
          if (n.nodeType === 3) {
            const frag = doc.createDocumentFragment();
            n.textContent.split(/(\s+)/).forEach((part) => {
              if (!part) return;
              if (/^\s+$/.test(part)) {
                frag.append(part);
                offset += part.length;
                return;
              }
              const w = doc.createElement("span");
              w.className = "wd";
              w.dataset.at = String(offset);
              w.textContent = part;
              frag.append(w);
              offset += part.length;
            });
            n.replaceWith(frag);
          } else if (n.nodeType === 1) walk(n);
        });
      };
      walk(text);
      page.dataset.speech = text.textContent.replace(/\s+/g, " ").trim();
    });

    // Rail state follows the reel on screen.
    const likeBtn = $(".rail__like", rail);
    const saveBtn = $(".rail__save", rail);
    const listenBtn = $(".rail__listen", rail);
    const goalLabel = $(".rail__goal small", rail);
    const goalIcon = $(".rail__goal", rail);
    const liked = new Set();
    const saved = new Set();
    const syncRail = () => {
      const text = isText(pages[current]);
      rail.style.visibility = text ? "visible" : "hidden";
      likeBtn?.setAttribute("aria-pressed", String(liked.has(current)));
      if (likeBtn) likeBtn.firstElementChild.outerHTML = liked.has(current) ? ICONS.heartFill : ICONS.heart;
      saveBtn?.setAttribute("aria-pressed", String(saved.has(current)));
    };

    const updateGoal = () => {
      const n = Math.min(counted.size, goalTarget);
      goalBar?.style.setProperty("--goal", String(n / goalTarget));
      if (goalLabel) goalLabel.textContent = `${n}/${goalTarget}`;
      if (n >= goalTarget && !goalMet) {
        goalMet = true;
        goalBar?.classList.add("is-met");
        if (goalIcon) goalIcon.firstElementChild.outerHTML = ICONS.met;
        toast("Today’s goal met 🎉");
      }
    };

    // Leaving a reel: it counts if it was really read (or heard).
    const leave = () => {
      const page = pages[current];
      if (!isText(page)) return;
      const dwell = performance.now() - shownAt;
      if (dwell >= dwellMs || page.dataset.heard === "1") {
        if (!counted.has(current)) {
          counted.add(current);
          updateGoal();
        }
      } else if (!counted.has(current) && !warnedQuick && dwell > 120) {
        warnedQuick = true;
        toast("Too quick to count — only real reading does");
      }
    };

    const onPage = () => {
      const i = Math.round(feed.scrollTop / feed.clientHeight);
      if (i === current) return;
      leave();
      current = clamp(i, 0, pages.length - 1);
      shownAt = performance.now();
      closeSheet();
      syncRail();
      if (speaking && isText(pages[current])) speak(pages[current]);
      else if (speaking) stopSpeaking(false);
    };
    let scrollEnd = 0;
    feed.addEventListener(
      "scroll",
      () => {
        clearTimeout(scrollEnd);
        scrollEnd = setTimeout(onPage, 90);
      },
      { passive: true },
    );
    const goTo = (i) => feed.scrollTo({ top: clamp(i, 0, pages.length - 1) * feed.clientHeight, behavior: reduced.matches ? "auto" : "smooth" });
    $$("[data-steer]", reel.closest("[data-demo]") || doc).forEach((b) =>
      b.addEventListener("click", () => goTo(current + (b.dataset.steer === "up" ? -1 : 1))),
    );
    feed.addEventListener("keydown", (e) => {
      if (["ArrowDown", "PageDown", " "].includes(e.key)) {
        e.preventDefault();
        goTo(current + 1);
      } else if (["ArrowUp", "PageUp"].includes(e.key)) {
        e.preventDefault();
        goTo(current - 1);
      }
    });

    // Double-tap to like, with a heart where you tapped.
    let lastTap = 0;
    const likeAt = (x, y) => {
      if (!isText(pages[current])) return;
      const r = reel.getBoundingClientRect();
      const burst = doc.createElement("div");
      burst.className = "burst";
      burst.innerHTML = ICONS.heartFill;
      burst.style.left = `${x - r.left}px`;
      burst.style.top = `${y - r.top}px`;
      reel.append(burst);
      setTimeout(() => burst.remove(), 950);
      if (!liked.has(current)) {
        liked.add(current);
        syncRail();
      }
    };
    feed.addEventListener("pointerup", (e) => {
      if (e.target.closest(".hard, button, a")) return;
      const now = performance.now();
      if (now - lastTap < 320) {
        likeAt(e.clientX, e.clientY);
        lastTap = 0;
      } else lastTap = now;
    });
    feed.addEventListener("dblclick", (e) => e.preventDefault());

    likeBtn?.addEventListener("click", () => {
      liked.has(current) ? liked.delete(current) : liked.add(current);
      syncRail();
    });
    saveBtn?.addEventListener("click", () => {
      const on = !saved.has(current);
      on ? saved.add(current) : saved.delete(current);
      syncRail();
      toast(on ? "Saved to your Notebook 🔖" : "Removed from saved");
    });
    $(".rail__note", rail)?.addEventListener("click", () => toast("Notes open in the app ✍️"));
    $(".rail__share", rail)?.addEventListener("click", async () => {
      const text = `${pages[current].dataset.speech}\n— Lewis Carroll, Alice’s Adventures in Wonderland`;
      try {
        if (navigator.share) await navigator.share({ title: "A reel from Cloro", text, url: location.origin + "/" });
        else {
          await navigator.clipboard.writeText(`${text}\n${location.origin}/`);
          toast("Quote copied");
        }
      } catch {
        /* the share sheet was closed */
      }
    });

    // A word's meaning, as in the app.
    const closeSheet = () => sheet?.classList.remove("is-open");
    reel.addEventListener("click", (e) => {
      const hard = e.target.closest(".hard");
      if (hard && sheet) {
        const lemma = hard.dataset.lemma;
        const senses = MEANINGS[lemma] || [];
        sheet.innerHTML =
          `<h4>${lemma}</h4><div class="kind">DICTIONARY</div>` +
          senses
            .map(([pos, gloss, ex]) => `<p><em>${pos}</em>${gloss}</p>${ex ? `<q>${ex}</q>` : ""}`)
            .join("") +
          `<button type="button">＋ Add to word list</button>`;
        $("button", sheet).addEventListener("click", () => {
          closeSheet();
          toast(`“${lemma}” added to your words`);
        });
        sheet.classList.add("is-open");
        return;
      }
      if (sheet?.classList.contains("is-open") && !e.target.closest(".sheet")) closeSheet();
    });

    // Listen: the browser's own voice (the app has a natural one, offline).
    let speaking = false;
    const synth = "speechSynthesis" in window ? window.speechSynthesis : null;
    const clearSaid = () => $$(".said", reel).forEach((w) => w.classList.remove("said"));
    const stopSpeaking = (keep = false) => {
      if (!keep) {
        speaking = false;
        listenBtn?.setAttribute("aria-pressed", "false");
      }
      synth?.cancel();
      clearSaid();
    };
    const speak = (page) => {
      if (!synth) return;
      synth.cancel();
      clearSaid();
      const u = new SpeechSynthesisUtterance(page.dataset.speech);
      u.lang = "en-GB";
      u.rate = 0.98;
      const words = $$(".wd", page);
      u.onboundary = (ev) => {
        if (ev.name && ev.name !== "word") return;
        words.forEach((w) => w.classList.toggle("said", Number(w.dataset.at) <= ev.charIndex));
      };
      u.onend = () => {
        page.dataset.heard = "1";
        if (!speaking || pages[current] !== page) return;
        if (current < pages.length - 1) goTo(current + 1);
        else stopSpeaking();
      };
      synth.speak(u);
    };
    listenBtn?.addEventListener("click", () => {
      if (!synth) return toast("Your browser has no voice here — the app does");
      if (speaking) return stopSpeaking();
      speaking = true;
      listenBtn.setAttribute("aria-pressed", "true");
      if (isText(pages[current])) speak(pages[current]);
      else goTo(current + 1);
    });
    new IntersectionObserver(([e]) => !e.isIntersecting && speaking && stopSpeaking()).observe(reel);

    // Scenes.
    const picks = $$("[data-scene-pick]", reel.closest("[data-demo]") || doc);
    const bg = $(".reel__bg", reel);
    picks.forEach((b) =>
      b.addEventListener("click", () => {
        const name = b.dataset.scenePick;
        picks.forEach((p) => p.setAttribute("aria-pressed", String(p === b)));
        paintScene(reel, name);
        if (name === "studyNight" && bgVideo) {
          bg.style.backgroundImage = "";
          bgVideo.hidden = false;
          if (!reduced.matches) bgVideo.play().catch(() => {});
        } else {
          bgVideo?.pause();
          if (bgVideo) bgVideo.hidden = true;
          bg.style.backgroundImage = `url("${b.dataset.src}")`;
        }
      }),
    );

    syncRail();
    updateGoal();
  });

  // ------------------------------------------------------------ gallery

  $$("[data-gallery]").forEach((g) => {
    const track = $(".gallery__track", g);
    const prev = $("[data-prev]", g);
    const next = $("[data-next]", g);
    const step = () => ($(".gallery__item", track)?.getBoundingClientRect().width || 300) + 26;
    const update = () => {
      if (prev) prev.disabled = track.scrollLeft < 8;
      if (next) next.disabled = track.scrollLeft + track.clientWidth > track.scrollWidth - 8;
    };
    prev?.addEventListener("click", () => track.scrollBy({ left: -step(), behavior: "smooth" }));
    next?.addEventListener("click", () => track.scrollBy({ left: step(), behavior: "smooth" }));
    track.addEventListener("scroll", update, { passive: true });
    addEventListener("resize", update);
    update();
    // Drag to scroll with a mouse.
    let down = null;
    track.addEventListener("pointerdown", (e) => {
      if (e.pointerType !== "mouse") return;
      down = { x: e.clientX, left: track.scrollLeft, moved: false };
    });
    addEventListener("pointermove", (e) => {
      if (!down) return;
      const dx = e.clientX - down.x;
      if (Math.abs(dx) > 4) {
        down.moved = true;
        track.classList.add("is-dragging");
      }
      track.scrollLeft = down.left - dx;
    });
    addEventListener("pointerup", () => {
      if (!down) return;
      const moved = down.moved;
      down = null;
      track.classList.remove("is-dragging");
      if (moved) {
        const items = $$(".gallery__item", track);
        const mid = track.scrollLeft + track.clientWidth / 2;
        let best = items[0];
        items.forEach((it) => {
          if (Math.abs(it.offsetLeft + it.offsetWidth / 2 - mid) < Math.abs(best.offsetLeft + best.offsetWidth / 2 - mid)) best = it;
        });
        track.scrollTo({ left: best.offsetLeft + best.offsetWidth / 2 - track.clientWidth / 2, behavior: "smooth" });
      }
    });
    track.addEventListener("click", (e) => track.classList.contains("is-dragging") && e.preventDefault(), true);
  });

  // --------------------------------------------------------- reading fonts

  $$("[data-fontshow]").forEach((box) => {
    const line = $(".fontshow", box);
    const chips = $$("[data-font]", box);
    let i = 0;
    let auto = 0;
    const pick = (k, user) => {
      i = k;
      line.classList.add("is-switching");
      setTimeout(() => {
        line.style.fontFamily = chips[k].dataset.font;
        line.classList.remove("is-switching");
      }, reduced.matches ? 0 : 220);
      chips.forEach((c, j) => c.setAttribute("aria-pressed", String(j === k)));
      if (user) clearInterval(auto);
    };
    chips.forEach((c, k) => c.addEventListener("click", () => pick(k, true)));
    pick(0);
    new IntersectionObserver(([e]) => {
      clearInterval(auto);
      if (e.isIntersecting && !reduced.matches) auto = setInterval(() => pick((i + 1) % chips.length), 2400);
    }).observe(box);
  });

  // --------------------------------------------------- languages, turning

  $$(".rotator").forEach((r) => {
    const items = $$("span", r);
    if (items.length < 2) return;
    let i = 0;
    items[0].classList.add("is-on");
    let t = 0;
    new IntersectionObserver(([e]) => {
      clearInterval(t);
      if (!e.isIntersecting || reduced.matches) return;
      t = setInterval(() => {
        const prev = items[i];
        i = (i + 1) % items.length;
        prev.classList.remove("is-on");
        prev.classList.add("is-off");
        setTimeout(() => prev.classList.remove("is-off"), 650);
        items[i].classList.add("is-on");
      }, 1700);
    }).observe(r);
  });

  // ------------------------------------------------- numbers, counting up

  $$("[data-count]").forEach((el) => {
    const to = Number(el.dataset.count);
    if (reduced.matches) return;
    el.textContent = "0";
    const io = new IntersectionObserver(([e]) => {
      if (!e.isIntersecting) return;
      io.disconnect();
      const t0 = performance.now();
      const run = (t) => {
        const p = clamp((t - t0) / 1400, 0, 1);
        el.textContent = String(Math.round(to * (1 - Math.pow(1 - p, 3))));
        if (p < 1) requestAnimationFrame(run);
      };
      requestAnimationFrame(run);
    });
    io.observe(el);
  });

  // ------------------------------------------------------------ pricing

  const segment = (group, onChange) => {
    const buttons = $$("button", group);
    const thumb = $(".segmented__thumb", group);
    const place = () => {
      const on = buttons.find((b) => b.getAttribute("aria-pressed") === "true") || buttons[0];
      if (!thumb || !on) return;
      thumb.style.width = `${on.offsetWidth}px`;
      thumb.style.transform = `translateX(${on.offsetLeft}px)`;
    };
    buttons.forEach((b) =>
      b.addEventListener("click", () => {
        buttons.forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
        place();
        onChange(b.dataset.value);
      }),
    );
    addEventListener("resize", place);
    doc.fonts?.ready.then(place);
    place();
    return (value) => {
      buttons.forEach((x) => x.setAttribute("aria-pressed", String(x.dataset.value === value)));
      place();
    };
  };
  const pricing = $("[data-pricing]");
  if (pricing) {
    const state = { period: "month", currency: "inr" };
    const fmt = (v, c) =>
      c === "inr"
        ? "₹" + Number(v).toLocaleString("en-IN")
        : "$" + Number(v).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const render = (animate = true) => {
      $$("[data-price]", pricing).forEach((el) => {
        const m = Number(el.dataset[`${state.currency}Month`]);
        const y = Number(el.dataset[`${state.currency}Year`]);
        const strong = $("strong", el);
        const per = $("span", el);
        const note = el.nextElementSibling?.matches(".price__note") ? el.nextElementSibling : null;
        const apply = () => {
          if (!m) {
            strong.textContent = state.currency === "inr" ? "₹0" : "$0";
            per.textContent = "forever";
            if (note) note.textContent = "";
          } else if (state.period === "month") {
            strong.textContent = fmt(m, state.currency);
            per.textContent = "/month";
            if (note) note.textContent = "";
          } else {
            strong.textContent = fmt(y, state.currency);
            per.textContent = "/year";
            const save = Math.round((1 - y / (m * 12)) * 100);
            if (note) note.textContent = `${fmt(Math.round((y / 12) * 100) / 100, state.currency)}/month · save ${save}%`;
          }
        };
        if (!animate || reduced.matches) return apply();
        el.classList.add("is-changing");
        setTimeout(() => {
          apply();
          el.classList.remove("is-changing");
        }, 170);
      });
      $$("[data-currency-note]", pricing).forEach((n) => (n.hidden = n.dataset.currencyNote !== state.currency));
      // AI books a month follow the region: India's, or everywhere else's.
      $$("[data-quota]", pricing).forEach((q) => (q.textContent = q.dataset[state.currency]));
    };
    const periodGroup = $("[data-toggle='period']", pricing);
    const currencyGroup = $("[data-toggle='currency']", pricing);
    if (periodGroup) segment(periodGroup, (v) => ((state.period = v), render()));
    let setCurrency = null;
    if (currencyGroup) setCurrency = segment(currencyGroup, (v) => ((state.currency = v), render()));
    // Rupees in India (and by default); dollars elsewhere.
    try {
      const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "";
      if (tz && !/Kolkata|Calcutta/.test(tz) && !/-IN$/i.test(navigator.language)) {
        state.currency = "usd";
        setCurrency?.("usd");
      }
    } catch {
      /* keep rupees */
    }
    render(false);
  }

  // --------------------------------------------------------------- FAQ

  $$(".faq details").forEach((d) => {
    const summary = $("summary", d);
    const body = $(".faq__body", d);
    if (!summary || !body) return;
    summary.addEventListener("click", (e) => {
      if (reduced.matches || !body.animate) return;
      e.preventDefault();
      if (d.open) {
        const h = body.offsetHeight;
        body.animate([{ height: `${h}px`, opacity: 1 }, { height: "0px", opacity: 0 }], { duration: 260, easing: "ease" }).onfinish = () => (d.open = false);
      } else {
        d.open = true;
        const h = body.offsetHeight;
        body.animate([{ height: "0px", opacity: 0 }, { height: `${h}px`, opacity: 1 }], { duration: 320, easing: "cubic-bezier(.16,1,.3,1)" });
      }
    });
  });

  // Help: search the questions as you type.
  const search = $("[data-faq-search]");
  if (search) {
    const items = $$("[data-faq] details");
    const groups = $$("[data-faq] .faq-group");
    const empty = $(".search-empty");
    const originals = new Map(items.map((d) => [d, d.innerHTML]));
    search.addEventListener("input", () => {
      const q = search.value.trim().toLowerCase();
      let any = false;
      items.forEach((d) => {
        d.innerHTML = originals.get(d);
        const hit = !q || d.textContent.toLowerCase().includes(q);
        d.hidden = !hit;
        if (hit) any = true;
        if (q && hit) {
          d.open = true;
          const walker = doc.createTreeWalker(d, NodeFilter.SHOW_TEXT);
          const nodes = [];
          while (walker.nextNode()) nodes.push(walker.currentNode);
          nodes.forEach((n) => {
            const i = n.textContent.toLowerCase().indexOf(q);
            if (i < 0) return;
            const mark = doc.createElement("mark");
            const range = doc.createRange();
            range.setStart(n, i);
            range.setEnd(n, i + q.length);
            range.surroundContents(mark);
          });
        } else if (!q) d.open = false;
      });
      groups.forEach((g) => (g.hidden = !$$("details", g).some((d) => !d.hidden)));
      empty?.classList.toggle("is-shown", !any);
    });
  }

  // ---------------------------------------------------------- copy email

  $$("[data-copy]").forEach((b) =>
    b.addEventListener("click", async () => {
      const label = $("span", b);
      const was = label.textContent;
      try {
        await navigator.clipboard.writeText(b.dataset.copy);
        label.textContent = "Copied";
      } catch {
        location.href = `mailto:${b.dataset.copy}`;
      }
      setTimeout(() => (label.textContent = was), 1600);
    }),
  );

  // ------------------------------------------ sub-navigation: where you are

  const subnav = $(".subnav");
  if (subnav) {
    const links = $$("a[href^='#']", subnav);
    const sections = links.map((a) => doc.getElementById(a.getAttribute("href").slice(1))).filter(Boolean);
    onFrame.push(() => {
      const line = innerHeight * 0.3;
      let current = sections[0];
      sections.forEach((s) => {
        if (s.getBoundingClientRect().top <= line) current = s;
      });
      links.forEach((a) => {
        const on = a.getAttribute("href") === `#${current?.id}`;
        if (on && !a.classList.contains("is-current")) a.scrollIntoView({ block: "nearest", inline: "center" });
        a.classList.toggle("is-current", on);
      });
    });
  }

  // ------------------------------------------------------------- footer

  $$("[data-year]").forEach((el) => (el.textContent = String(new Date().getFullYear())));

  schedule();
})();
