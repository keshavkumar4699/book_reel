#!/usr/bin/env node
// Checks website/public before it ships (no dependencies). For every page:
//
// - lang, charset, viewport; a title of 10–70 characters and a meta
//   description of 50–170, neither shared with another page; one <h1>;
// - indexable pages: a canonical https://cloro.in URL for their own path,
//   Open Graph and Twitter tags, a social image that exists;
// - JSON-LD that parses;
// - every internal link, #fragment, image, srcset entry, video, poster,
//   stylesheet and script points at something that exists; images have alt,
//   width and height; external links use https.
//
// And for the site: sitemap.xml lists exactly the indexable pages, robots.txt
// names it, the stylesheet's url()s exist, and the built parts are current.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { pages } from "./build.mjs";

const here = fileURLToPath(new URL(".", import.meta.url));
const pub = join(here, "..", "public");
const ORIGIN = "https://cloro.in";
const problems = [];
const fail = (where, what) => problems.push(`${where}: ${what}`);
const read = (p) => readFileSync(p, "utf8");
const attr = (tag, name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];
const metaContent = (html, key, value) => html.match(new RegExp(`<meta ${key}="${value}" content="([^"]*)"`))?.[1];

/** The file a site path is served from, or null. */
function fileFor(path) {
  const clean = decodeURIComponent(path.split(/[?#]/)[0]);
  const local = join(pub, clean);
  if (clean.endsWith("/")) return existsSync(join(local, "index.html")) ? join(local, "index.html") : null;
  if (existsSync(local)) return local;
  return null;
}
const idsCache = new Map();
const idsOf = (file) => {
  if (!idsCache.has(file)) idsCache.set(file, new Set([...read(file).matchAll(/\sid="([^"]+)"/g)].map((m) => m[1])));
  return idsCache.get(file);
};

const list = pages();
const titles = new Map();
const descriptions = new Map();
const indexable = [];

for (const page of list) {
  const html = read(page.file);
  const where = page.rel;
  const noindex = /<meta name="robots" content="[^"]*noindex/.test(html);
  if (!/^<!doctype html>/i.test(html)) fail(where, "no <!doctype html>");
  if (!/<html lang="en"/.test(html)) fail(where, 'no <html lang="en">');
  if (!/<meta charset="utf-8">/.test(html)) fail(where, "no charset");
  if (!/<meta name="viewport"/.test(html)) fail(where, "no viewport (is <!-- head --> filled? run npm run build)");
  const title = html.match(/<title>([^<]*)<\/title>/)?.[1];
  if (!title) fail(where, "no <title>");
  else {
    const t = title.replace(/&amp;/g, "&");
    if (t.length < 10 || t.length > 70) fail(where, `title is ${t.length} characters (10–70): ${t}`);
    if (titles.has(t)) fail(where, `title also on ${titles.get(t)}`);
    titles.set(t, where);
  }
  const description = metaContent(html, "name", "description");
  if (!description) fail(where, "no meta description");
  else {
    if (description.length < 50 || description.length > 170) fail(where, `description is ${description.length} characters (50–170)`);
    if (descriptions.has(description)) fail(where, `description also on ${descriptions.get(description)}`);
    descriptions.set(description, where);
  }
  const h1s = (html.match(/<h1[\s>]/g) || []).length;
  if (h1s !== 1) fail(where, `${h1s} <h1> elements (want 1)`);

  if (!noindex) {
    indexable.push(page.url);
    const canonical = html.match(/<link rel="canonical" href="([^"]+)">/)?.[1];
    if (canonical !== ORIGIN + page.url) fail(where, `canonical ${canonical} (want ${ORIGIN + page.url})`);
    for (const p of ["og:title", "og:description", "og:url", "og:image", "og:type", "og:site_name"]) {
      if (!metaContent(html, "property", p)) fail(where, `no ${p}`);
    }
    if (metaContent(html, "property", "og:url") !== ORIGIN + page.url) fail(where, "og:url is not the canonical URL");
    for (const n of ["twitter:card", "twitter:title", "twitter:description", "twitter:image"]) {
      if (!metaContent(html, "name", n)) fail(where, `no ${n}`);
    }
    for (const img of [metaContent(html, "property", "og:image"), metaContent(html, "name", "twitter:image")]) {
      if (!img?.startsWith(ORIGIN + "/")) fail(where, `social image ${img} isn't an absolute ${ORIGIN} URL`);
      else if (!fileFor(img.slice(ORIGIN.length))) fail(where, `social image ${img} doesn't exist`);
    }
  }

  for (const m of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try {
      JSON.parse(m[1]);
    } catch (e) {
      fail(where, `JSON-LD doesn't parse: ${e.message}`);
    }
  }

  // Links and the files a page uses.
  const refs = [];
  for (const m of html.matchAll(/<a\s[^>]*>/g)) refs.push(["link", attr(m[0], "href")]);
  for (const m of html.matchAll(/<(?:img|source|script|video)\s[^>]*>/g)) {
    refs.push(["src", attr(m[0], "src")]);
    refs.push(["poster", attr(m[0], "poster")]);
    for (const part of (attr(m[0], "srcset") || "").split(",")) refs.push(["srcset", part.trim().split(/\s+/)[0]]);
  }
  for (const m of html.matchAll(/<link\s[^>]*>/g)) if (!/rel="canonical"/.test(m[0])) refs.push(["href", attr(m[0], "href")]);
  for (const m of html.matchAll(/data-src="([^"]+)"/g)) refs.push(["data-src", m[1]]);
  for (const [kind, ref] of refs) {
    if (!ref) continue;
    if (ref.startsWith("#")) {
      if (ref.length > 1 && !idsOf(page.file).has(ref.slice(1))) fail(where, `${kind} ${ref}: no such id`);
    } else if (ref.startsWith("/") && !ref.startsWith("//")) {
      const target = fileFor(ref);
      if (!target) fail(where, `${kind} ${ref} doesn't exist`);
      else {
        const hash = ref.split("#")[1];
        if (hash && target.endsWith(".html") && !idsOf(target).has(hash)) fail(where, `${kind} ${ref}: no such id`);
      }
    } else if (/^http:/.test(ref)) fail(where, `${kind} ${ref} isn't https`);
    else if (!/^(https:|mailto:|tel:|data:)/.test(ref)) fail(where, `${kind} ${ref}: use a root-relative path`);
  }
  for (const m of html.matchAll(/<img\s[^>]*>/g)) {
    for (const a of ["alt", "width", "height"]) if (!new RegExp(`\\s${a}="`).test(m[0])) fail(where, `<img> without ${a}: ${m[0].slice(0, 90)}`);
  }
}

// The stylesheet's own files.
const css = read(join(pub, "assets/css/site.css"));
for (const m of css.matchAll(/url\("?(\/[^")]+)"?\)/g)) if (!fileFor(m[1])) fail("assets/css/site.css", `url(${m[1]}) doesn't exist`);

// The sitemap: exactly the indexable pages.
const sitemap = read(join(pub, "sitemap.xml"));
const listed = new Set([...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1].slice(ORIGIN.length)));
for (const url of indexable) if (!listed.has(url)) fail("sitemap.xml", `missing ${url}`);
for (const url of listed) if (!indexable.includes(url)) fail("sitemap.xml", `lists ${url}, which isn't an indexable page`);
if (!/^Sitemap: https:\/\/cloro\.in\/sitemap\.xml$/m.test(read(join(pub, "robots.txt")))) fail("robots.txt", "doesn't name the sitemap");
JSON.parse(read(join(pub, "site.webmanifest")));

// The built parts are current.
try {
  execFileSync(process.execPath, [join(here, "build.mjs"), "--check"], { stdio: "pipe" });
} catch (e) {
  fail("build", String(e.stderr || e.stdout).trim());
}

if (problems.length) {
  console.error(`${problems.length} problem${problems.length === 1 ? "" : "s"}:\n  ${problems.join("\n  ")}`);
  process.exit(1);
}
console.log(`All good: ${list.length} pages, ${indexable.length} in the sitemap.`);
