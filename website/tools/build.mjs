#!/usr/bin/env node
// Builds the parts of website/public that come from elsewhere, so every page
// stays plain HTML that any static host can serve:
//
// - the shared <head> tags, nav and footer (tools/partials) into every page,
//   between <!-- head -->…<!-- /head --> style markers, with the current
//   page marked in the nav;
// - /privacy/ and /terms/ from app/assets/legal/*.md: one text for the app,
//   the server and the site;
// - a version on the stylesheet and script links (a hash of each file), so
//   they can be cached for a year;
// - sitemap.xml: every page that isn't noindex, with its last change.
//
//   node tools/build.mjs           write
//   node tools/build.mjs --check   change nothing; fail if anything is stale

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const site = resolve(here, "..");
const pub = join(site, "public");
const legalDir = resolve(site, "../app/assets/legal");
const ORIGIN = "https://cloro.in";
const check = process.argv.includes("--check");

const read = (p) => readFileSync(p, "utf8");
const hash = (p) => createHash("sha256").update(readFileSync(p)).digest("hex").slice(0, 10);
const escape = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

/** Every HTML page under public/, with its URL path. */
export function pages() {
  const out = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) {
        if (name !== "assets") walk(p);
      } else if (name.endsWith(".html")) {
        const rel = relative(pub, p).split(sep).join("/");
        const url = "/" + rel.replace(/(^|\/)index\.html$/, "$1");
        out.push({ file: p, rel, url });
      }
    }
  };
  walk(pub);
  return out.sort((a, b) => a.url.localeCompare(b.url));
}

// ---------------------------------------------------------------- partials

const partials = {
  head: () => read(join(here, "partials/head.html")).replace("{{css}}", hash(join(pub, "assets/css/site.css"))).replace("{{js}}", hash(join(pub, "assets/js/site.js"))),
  nav: (url) =>
    read(join(here, "partials/nav.html")).replace(/href="([^"]+)"(?=[^>]*>(?!<img))/g, (m, href) =>
      href === url || (href !== "/" && url.startsWith(href) && href.endsWith("/")) ? `${m} aria-current="page"` : m,
    ),
  footer: () => read(join(here, "partials/footer.html")),
};

const decode = (s) =>
  s
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();

/** The questions on a page (each <details> with its summary and answer). */
export function questions(html) {
  const out = [];
  const re = /<details>\s*<summary>([\s\S]*?)<\/summary>\s*<div class="faq__body">([\s\S]*?)<\/div>\s*<\/details>/g;
  for (const m of html.matchAll(re)) out.push({ q: decode(m[1]), a: decode(m[2].replace(/<\/(p|li)>/g, " $&")) });
  return out;
}

/** FAQPage data for a page's questions, exactly as they're shown. */
const faqJson = (html, url) => {
  const title = decode(html.match(/<title>([\s\S]*?)<\/title>/)?.[1] ?? "").split(/ [—|] /)[0];
  const crumb = html.match(/aria-current="page">([^<]+)</)?.[1] ?? title;
  const data = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "FAQPage",
        "@id": `${ORIGIN}${url}#faq`,
        url: `${ORIGIN}${url}`,
        mainEntity: questions(html).map(({ q, a }) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: a } })),
      },
      {
        "@type": "BreadcrumbList",
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "Cloro", item: `${ORIGIN}/` },
          { "@type": "ListItem", position: 2, name: crumb, item: `${ORIGIN}${url}` },
        ],
      },
    ],
  };
  return `<script type="application/ld+json">\n${JSON.stringify(data, null, 2)}\n</script>`;
};

/** The page with its shared blocks filled in. */
export function fill(html, url) {
  for (const [name, make] of Object.entries(partials)) {
    const re = new RegExp(`(<!-- ${name} -->)[\\s\\S]*?(<!-- /${name} -->)`);
    if (!re.test(html)) continue;
    html = html.replace(re, (_, open, close) => `${open}\n${make(url).trim()}\n${close}`);
  }
  const faq = /(<!-- faq -->)[\s\S]*?(<!-- \/faq -->)/;
  if (faq.test(html)) html = html.replace(faq, (_, open, close) => `${open}\n${faqJson(html, url)}\n${close}`);
  return html;
}

// ------------------------------------------------------------ legal pages

/** Inline Markdown: **bold**, email addresses and cloro.in addresses as links (escaped first). */
const inline = (s) =>
  escape(s)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/([\w.+-]+@[\w-]+(?:\.[\w-]+)+)|(?<![@\w.])cloro\.in(\/[\w/-]*)?/g, (m, email, path = "/") =>
      email ? `<a href="mailto:${email}">${email}</a>` : `<a href="${path.endsWith("/") ? path : path + "/"}">${m}</a>`,
    );

/**
 * The part of Markdown the legal texts use (as server/src/legal.ts):
 * # and ## headings, paragraphs, "- " lists, tables and **bold**. A first
 * paragraph saying it's a draft is shown as a notice.
 */
export function markdownToHtml(md) {
  const out = [];
  let para = [];
  let list = [];
  let table = [];
  const flush = () => {
    if (para.length) {
      const text = para.join(" ");
      out.push(/^Draft for review/i.test(text) ? `<p class="notice">${inline(text)}</p>` : `<p>${inline(text)}</p>`);
    }
    if (list.length) out.push(`<ul>${list.map((l) => `<li>${inline(l)}</li>`).join("")}</ul>`);
    if (table.length) {
      const [head, ...rows] = table;
      out.push(
        `<table><thead><tr>${head.map((c) => `<th scope="col">${inline(c)}</th>`).join("")}</tr></thead><tbody>` +
          rows.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`).join("") +
          `</tbody></table>`,
      );
    }
    para = [];
    list = [];
    table = [];
  };
  for (const raw of md.replace(/\r\n/g, "\n").split("\n")) {
    const line = raw.trimEnd();
    if (!line.trim()) flush();
    else if (line.startsWith("## ")) {
      flush();
      const text = line.slice(3);
      const id = text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
      out.push(`<h2 id="${id}">${inline(text)}</h2>`);
    } else if (line.startsWith("# ")) {
      flush();
      out.push(`<h1>${inline(line.slice(2))}</h1>`);
    } else if (line.startsWith("- ")) {
      if (para.length || table.length) flush();
      list.push(line.slice(2));
    } else if (line.startsWith("|")) {
      if (para.length || list.length) flush();
      const cells = line.slice(1, line.endsWith("|") ? -1 : undefined).split("|").map((c) => c.trim());
      if (!cells.every((c) => /^:?-{3,}:?$/.test(c))) table.push(cells);
    } else {
      if (list.length || table.length) flush();
      para.push(line.trim());
    }
  }
  flush();
  return out.join("\n");
}

const LEGAL = [
  {
    doc: "privacy",
    title: "Privacy policy",
    description: "What Cloro keeps, what stays on your phone, who processes data for us, and how to download your data or delete your account.",
  },
  {
    doc: "terms",
    title: "Terms of use",
    description: "The terms for using Cloro: your books, your account, community rules, subscriptions through Google Play, and AI output.",
  },
];

function legalPage({ doc, title, description }) {
  const url = `/${doc}/`;
  const body = markdownToHtml(read(join(legalDir, `${doc}.md`)));
  const crumbs = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Cloro", item: `${ORIGIN}/` },
      { "@type": "ListItem", position: 2, name: title, item: `${ORIGIN}${url}` },
    ],
  };
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${title} | Cloro</title>
<meta name="description" content="${escape(description)}">
<link rel="canonical" href="${ORIGIN}${url}">
<meta name="robots" content="index, follow">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Cloro">
<meta property="og:locale" content="en_IN">
<meta property="og:url" content="${ORIGIN}${url}">
<meta property="og:title" content="${title} | Cloro">
<meta property="og:description" content="${escape(description)}">
<meta property="og:image" content="${ORIGIN}/og/default.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Cloro: read like you scroll.">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${title} | Cloro">
<meta name="twitter:description" content="${escape(description)}">
<meta name="twitter:image" content="${ORIGIN}/og/default.jpg">
<!-- head -->
<!-- /head -->
<script type="application/ld+json">
${JSON.stringify(crumbs, null, 2)}
</script>
</head>
<body>
<!-- nav -->
<!-- /nav -->
<main id="main">
  <!-- Generated by tools/build.mjs from app/assets/legal/${doc}.md: edit that file, then run npm run build. -->
  <article class="wrap--narrow page-head prose" style="padding-bottom:var(--section)">
    <nav aria-label="Breadcrumb"><ol class="crumbs" role="list"><li><a href="/">Cloro</a></li><li aria-current="page">${title}</li></ol></nav>
${body}
  </article>
</main>
<!-- footer -->
<!-- /footer -->
</body>
</html>
`;
}

// ---------------------------------------------------------------- sitemap

const lastChange = (file) => {
  try {
    const d = execFileSync("git", ["log", "-1", "--format=%cs", "--", file], { cwd: site, encoding: "utf8" }).trim();
    const dirty = execFileSync("git", ["status", "--porcelain", "--", file], { cwd: site, encoding: "utf8" }).trim();
    if (d && !dirty) return d;
  } catch {
    /* not a git checkout */
  }
  return new Date().toISOString().slice(0, 10);
};

export function sitemap(list) {
  const urls = list
    .filter((p) => !/<meta name="robots" content="[^"]*noindex/.test(read(p.file)) && !p.rel.startsWith("404"))
    .map((p) => {
      const legal = LEGAL.find((l) => p.url === `/${l.doc}/`);
      const date = lastChange(legal ? join(legalDir, `${legal.doc}.md`) : p.file);
      return `  <url>\n    <loc>${ORIGIN}${p.url}</loc>\n    <lastmod>${date}</lastmod>\n  </url>`;
    });
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join("\n")}\n</urlset>\n`;
}

// ------------------------------------------------------------------- main

function main() {
  const stale = [];
  const write = (file, text, { ignore } = {}) => {
    const before = existsSync(file) ? read(file) : null;
    const same = ignore ? before?.replace(ignore, "") === text.replace(ignore, "") : before === text;
    if (same) return;
    if (check) stale.push(relative(site, file));
    else {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, text);
      console.log("wrote", relative(site, file));
    }
  };
  for (const l of LEGAL) write(join(pub, l.doc, "index.html"), fill(legalPage(l), `/${l.doc}/`));
  const list = pages();
  for (const p of list) {
    if (LEGAL.some((l) => p.url === `/${l.doc}/`)) continue;
    write(p.file, fill(read(p.file), p.url));
  }
  write(join(pub, "sitemap.xml"), sitemap(list), { ignore: /<lastmod>[^<]*<\/lastmod>/g });
  if (check && stale.length) {
    console.error(`Out of date (run npm run build):\n  ${stale.join("\n  ")}`);
    process.exit(1);
  }
  if (check) console.log("Built files are up to date.");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
