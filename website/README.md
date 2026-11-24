# cloro.in

The Cloro website: a fast, static, Apple-style site in plain HTML, CSS and JavaScript. It has no framework and no runtime dependencies.

```
website/
  public/              the site, as deployed (every page is complete HTML)
    index.html         home: hero, how it reads, a live reel to try, scenes and fonts, privacy, plans
    features/          everything the app does, section by section
    pricing/           plans in ₹ and $, monthly or yearly, and a comparison
    download/          Google Play, a QR code for computers, requirements
    support/           searchable answers and contact
    about/             why Cloro exists
    privacy/, terms/   generated from app/assets/legal/*.md (don't edit here)
    account/delete/    how to delete an account (the URL Google Play asks for)
    404.html, robots.txt, sitemap.xml, site.webmanifest, .well-known/security.txt
    assets/            css/site.css, js/site.js, fonts (subset WOFF2), img, video
    og/                social preview images, 1200 × 630
  tools/
    partials/          the <head> tags, nav and footer every page shares
    build.mjs          fills the shared parts in, builds privacy and terms, versions CSS/JS, writes the sitemap
    check.mjs          checks every page: SEO tags, links, images, structured data, sitemap
    screens.py         app screenshots → the site's WebP images and the hero's moving scene
    og/og.html, og.cjs the social preview images
  firebase.json        hosting: clean URLs, caching, security headers, routes to the server
```

## Working on it

```bash
cd website
npm run serve        # http://localhost:8080
```

- **Change a page:** edit its `public/…/index.html`.
- **Change the nav, footer or `<head>`:** edit the file in `tools/partials/`. Each page marks where those go with `<!-- nav -->…<!-- /nav -->` style comments.
- **Change the privacy policy or terms:** edit `app/assets/legal/*.md`. The app, the server and the site all show that one text.
- **Questions on Support:** edit the `<details>` blocks. The structured data for search engines is rebuilt from them, so the two always match.

After any change:

```bash
npm run build        # fills in shared parts, rebuilds legal pages, versions CSS/JS, updates the sitemap
npm run check        # fails on a broken link, a missing tag or image, or an out-of-date build
```

CI runs `npm run check` on every push.

### What makes it fast and findable

- **Search:** every page has its own title, description and canonical URL, plus Open Graph and Twitter cards with a 1200 × 630 image. Structured data (JSON-LD) covers:
  - the organisation, the website and the app (`MobileApplication`, with its plans as offers);
  - breadcrumbs, and the FAQ on Support.
- **Crawling:** `sitemap.xml` lists every indexable page with its last change; `robots.txt` points to it.
- **Speed:**
  - two subset fonts (about 30 KB each), plus 2 KB cuts of each showcase font;
  - WebP images at 1× and 2× with width and height set;
  - images below the fold load lazily, and the hero video loads only when on screen;
  - no third-party requests at all.
- **Sharing on Android:** `site.webmanifest` names the Play app as the related app, so Chrome on Android can offer it.
- **Accessibility:**
  - semantic HTML, a skip link, focus rings and ARIA on interactive parts;
  - it works without JavaScript;
  - all motion stops for `prefers-reduced-motion`.

### The interactive parts (`assets/js/site.js`)

Each part runs only on pages that have it:
- the nav and its mobile menu;
- scroll reveals;
- the hero's reels turning by themselves over the moving Night desk scene;
- the manifesto lighting up word by word;
- the phone that follows the "How it reads" steps;
- the live reel demo: swipe, double-tap to like, tap a word for its meaning (WordNet, as in the app), Listen with the browser's voice, scenes, and a goal that only counts real reading;
- carousels, the font showcase, the pricing toggles, FAQ search and the Features page's section bar.

### Images

The phone screenshots are the real app, rendered from its widgets with sample reading. To redo them after the app's look changes:

```bash
cd app
CLORO_SCREENSHOTS=/tmp/cloro-shots flutter test test/marketing/screenshots_test.dart
cd ../website
npm run screens -- /tmp/cloro-shots     # needs Pillow, ffmpeg (libvpx) and Noto Color Emoji
npm run og                              # social images; needs Playwright with Chromium
```

The logo SVGs in `assets/img/brand/` are vector versions of `app/branding/logo.png` and `app/assets/images/logo_512.png`.

## Deploying (Firebase Hosting)

Firebase Hosting can live in the same Google Cloud project as the server. It serves this folder and routes these paths on `cloro.in` to the Cloud Run service `cloro-api` (asia-southeast1):
- `/c/…`: share links;
- `/i/…`: invites;
- `/.well-known/assetlinks.json`: Android App Links.

So those links work on `cloro.in` itself. Change the service or region in `firebase.json` if yours differ.

One time:

```bash
npm install -g firebase-tools
firebase login
cd website && firebase use --add        # pick the Google Cloud project the server runs in
```

Then deploy:

```bash
npm run deploy
```

In the Firebase console, go to **Hosting → Add custom domain**:
1. Add `cloro.in` and set the DNS records it shows at your domain registrar.
2. Add `www.cloro.in` as a redirect to `cloro.in`.

On the server, set `PUBLIC_BASE_URL=https://cloro.in` so share and invite links use the site's domain, and `SUPPORT_EMAIL=support@cloro.in`.

Elsewhere: `public/` works on any static host. Netlify, Cloudflare Pages and GitHub Pages serve `/features/` from `features/index.html`. They won't route `/c/` and `/i/` to the server, though: point those at the server's own address instead.

## Before launch

- [ ] Create the **support@cloro.in** mailbox (a forwarding address is enough). It appears on Support, About, Delete account, in `security.txt` and in the structured data.
- [ ] Fill in the [bracketed] parts of `app/assets/legal/privacy.md` and `terms.md`, have them reviewed, then run `npm run build`. Until then, both pages show the draft notice.
- [ ] Publish the app on Google Play. Every download button links to `https://play.google.com/store/apps/details?id=app.sweatik2.cloro`.
- [ ] Make Play Console's prices and free trials match the pricing page (`docs/DESIGN.md` §6.1). The page shows India and US prices; Play shows each reader their local price.
- [ ] In [Google Search Console](https://search.google.com/search-console), add `cloro.in` (DNS verification), submit `https://cloro.in/sitemap.xml`, and check a page with the URL Inspection tool.
- [ ] Put `https://cloro.in/privacy/` in Play Console (App content → Privacy policy) and `https://cloro.in/account/delete/` in the Data safety form's account deletion field.
